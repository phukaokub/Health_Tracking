package normalization

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"io"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/nkiri/xls"
)

const (
	LegacyXLSParserVersion = "huawei-legacy-xls-v1"
	LegacyXLSSourceFamily  = "huawei_legacy_xls"
	MaxLegacyXLSBytes      = 16 * 1024 * 1024
	maxLegacySheets        = 64
	maxLegacyRows          = 100_000
	maxLegacyColumns       = 128
	maxLegacySSTEntries    = 100_000
)

var legacySheetAllowlist = map[string]struct{}{
	"Daily Health Statistics": {},
	"Daily Sport Statistics":  {},
	"Sport Dimensions":        {},
	"Health Reports":          {},
	"Trend Reports":           {},
}

type LegacyXLSQuality struct {
	ApprovedSheetCount   int `json:"approved_sheet_count"`
	ExcludedSheetCount   int `json:"excluded_sheet_count"`
	UnknownSheetCount    int `json:"unknown_sheet_count"`
	CoveredDateCount     int `json:"covered_date_count"`
	CandidateMetricCount int `json:"candidate_metric_count"`
	AmbiguousCellCount   int `json:"ambiguous_cell_count"`
}

type legacyMetric struct {
	sourceType string
	unit       string
	multiplier float64
}

var legacyHeaders = map[string]legacyMetric{
	"steps":                    {"steps", "count", 1},
	"calories (kcal)":          {"calories", "kilocalories", 1},
	"distance (km)":            {"distance", "metres", 1000},
	"active minutes":           {"active_duration", "seconds", 60},
	"floors":                   {"floors", "count", 1},
	"resting heart rate (bpm)": {"resting_heart_rate", "bpm", 1},
	"average heart rate (bpm)": {"heart_rate", "bpm", 1},
}

// ParseLegacyXLS reads the deliberately narrow BIFF8 contract. It accepts only
// allowlisted sheet/header names and emits safe warning codes, never workbook
// values or names.
func ParseLegacyXLS(reader io.Reader, timezone string) (result Result, err error) {
	location, err := time.LoadLocation(timezone)
	if err != nil {
		return Result{}, &SafeError{Code: "timezone_invalid"}
	}
	data, err := io.ReadAll(io.LimitReader(reader, MaxLegacyXLSBytes+1))
	if err != nil || len(data) == 0 || len(data) > MaxLegacyXLSBytes {
		return Result{}, &SafeError{Code: "xls_size_limit"}
	}
	if err := preflightBIFF8(data); err != nil {
		return Result{}, err
	}
	defer func() {
		if recover() != nil {
			result = Result{}
			err = &SafeError{Code: "xls_malformed"}
		}
	}()
	workbook, err := xls.Read(bytes.NewReader(data))
	if err != nil || workbook == nil || workbook.SheetCount() > maxLegacySheets {
		return Result{}, &SafeError{Code: "xls_malformed"}
	}
	result.LegacyXLSQuality = &LegacyXLSQuality{}
	dates := map[string]struct{}{}
	rowsSeen := 0
	for sheetIndex := 0; sheetIndex < workbook.SheetCount(); sheetIndex++ {
		sheet := workbook.Sheet(sheetIndex)
		if sheet == nil {
			return Result{}, &SafeError{Code: "xls_malformed"}
		}
		name := strings.TrimSpace(sheet.Name())
		if _, approved := legacySheetAllowlist[name]; !approved {
			if isExplicitlyExcludedSheet(name) {
				result.LegacyXLSQuality.ExcludedSheetCount++
				result.Warnings = append(result.Warnings, Warning{Code: "xls_sheet_excluded"})
			} else {
				result.LegacyXLSQuality.UnknownSheetCount++
				result.Warnings = append(result.Warnings, Warning{Code: "xls_sheet_unknown"})
			}
			continue
		}
		result.LegacyXLSQuality.ApprovedSheetCount++
		if sheet.RowCount() < 1 {
			continue
		}
		header := sheet.Row(0)
		if header == nil || header.CellCount() > maxLegacyColumns {
			return Result{}, &SafeError{Code: "xls_schema_unsupported"}
		}
		dateColumn := -1
		metrics := map[int]legacyMetric{}
		for column := 0; column < header.CellCount(); column++ {
			value := normalizedCell(header.Cell(column))
			if value == "date" {
				dateColumn = column
			} else if metric, ok := legacyHeaders[value]; ok {
				metrics[column] = metric
			}
		}
		if dateColumn < 0 {
			result.Warnings = append(result.Warnings, Warning{Code: "xls_date_column_missing"})
			continue
		}
		for rowIndex := 1; rowIndex < sheet.RowCount(); rowIndex++ {
			rowsSeen++
			if rowsSeen > maxLegacyRows {
				return Result{}, &SafeError{Code: "xls_row_limit"}
			}
			row := sheet.Row(rowIndex)
			if row == nil || row.CellCount() > maxLegacyColumns {
				return Result{}, &SafeError{Code: "xls_schema_unsupported"}
			}
			localDate, parseErr := time.ParseInLocation("2006-01-02", normalizedCell(row.Cell(dateColumn)), location)
			if parseErr != nil {
				result.LegacyXLSQuality.AmbiguousCellCount++
				result.Warnings = append(result.Warnings, Warning{Code: "xls_date_ambiguous"})
				continue
			}
			end := localDate.AddDate(0, 0, 1)
			dateKey := localDate.Format("2006-01-02")
			for column := 0; column < row.CellCount(); column++ {
				metric, mapped := metrics[column]
				if !mapped {
					continue
				}
				text := normalizedCell(row.Cell(column))
				if text == "" {
					continue
				}
				value, parseErr := strconv.ParseFloat(text, 64)
				if parseErr != nil || math.IsNaN(value) || math.IsInf(value, 0) || value < 0 {
					result.LegacyXLSQuality.AmbiguousCellCount++
					result.Warnings = append(result.Warnings, Warning{Code: "xls_cell_ambiguous"})
					continue
				}
				value *= metric.multiplier
				canonical := strconv.FormatFloat(value, 'f', -1, 64)
				sourceHash := legacyHash(strings.Join([]string{name, dateKey, metric.sourceType}, "|"))
				result.Samples = append(result.Samples, Sample{
					SourceFamily: LegacyXLSSourceFamily, SourceType: metric.sourceType,
					SourceRecordHash: sourceHash, StartedAt: localDate.UTC(), EndedAt: end.UTC(),
					Unit: metric.unit, SourceUnit: header.Cell(column).Value(),
					UnitConversionVersion: "v1", Value: canonical,
					DedupeKey: legacyDailyDedupeKey(metric.sourceType, dateKey, timezone, metric.unit), ParserVersion: LegacyXLSParserVersion,
					CanonicalDay: dateKey, TimezoneResolution: "import_timezone",
				})
				result.LegacyXLSQuality.CandidateMetricCount++
				dates[dateKey] = struct{}{}
			}
		}
	}
	result.LegacyXLSQuality.CoveredDateCount = len(dates)
	return result, nil
}

func normalizedCell(cell *xls.Cell) string {
	if cell == nil {
		return ""
	}
	return strings.ToLower(strings.Join(strings.Fields(strings.TrimSpace(cell.Value())), " "))
}

func isExplicitlyExcludedSheet(name string) bool {
	value := strings.ToLower(strings.Join(strings.Fields(name), " "))
	for _, marker := range []string{"membership", "purchase", "card", "ranking", "agreement", "route", "ecg", "rri"} {
		if strings.Contains(value, marker) {
			return true
		}
	}
	return false
}

func preflightBIFF8(data []byte) error {
	if len(data) < 512 || binary.LittleEndian.Uint64(data[:8]) != 0xE11AB1A1E011CFD0 {
		return &SafeError{Code: "xls_malformed"}
	}
	for offset := 0; offset+12 <= len(data); offset++ {
		if data[offset] != 0xfc || data[offset+1] != 0x00 {
			continue
		}
		recordLength := int(binary.LittleEndian.Uint16(data[offset+2 : offset+4]))
		if recordLength < 8 || offset+4+recordLength > len(data) {
			continue
		}
		unique := binary.LittleEndian.Uint32(data[offset+8 : offset+12])
		if unique > maxLegacySSTEntries {
			return &SafeError{Code: "xls_string_limit"}
		}
	}
	return nil
}

func legacyHash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func legacyDailyDedupeKey(sourceType, date, timezone, unit string) string {
	return legacyHash(strings.Join([]string{"v1", LegacyXLSSourceFamily, sourceType, date, timezone, unit}, "|"))
}

func LegacyXLSAllowlistedSheets() []string {
	return []string{"Daily Health Statistics", "Daily Sport Statistics", "Sport Dimensions", "Health Reports", "Trend Reports"}
}
