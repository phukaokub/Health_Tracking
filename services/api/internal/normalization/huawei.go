// Package normalization converts approved, sanitized Huawei JSON records into
// canonical wellness samples. It has no provider, database, logging, or raw
// payload retention dependencies.
package normalization

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
)

const (
	ParserVersion  = "huawei-json-v1"
	MaxInputBytes  = 20 * 1024 * 1024
	MaxRecordBytes = 1 * 1024 * 1024
	MaxRecordCount = 10000
	SourceFamily   = "huawei_health_json"
)

type SafeError struct{ Code string }

func (err *SafeError) Error() string { return err.Code }

type Warning struct {
	Code string `json:"code"`
}

type Sample struct {
	SourceFamily     string    `json:"source_family"`
	SourceType       string    `json:"source_type"`
	SourceRecordHash string    `json:"source_record_hash"`
	StartedAt        time.Time `json:"started_at"`
	EndedAt          time.Time `json:"ended_at"`
	Unit             string    `json:"unit"`
	Value            string    `json:"value"`
	DedupeKey        string    `json:"dedupe_key"`
	ParserVersion    string    `json:"parser_version"`
}

type Result struct {
	Samples  []Sample  `json:"samples"`
	Warnings []Warning `json:"warnings"`
}

type sourceRecord struct {
	Type      string          `json:"type"`
	RecordID  string          `json:"record_id"`
	StartedAt string          `json:"started_at"`
	EndedAt   string          `json:"ended_at"`
	Unit      string          `json:"unit"`
	Value     json.RawMessage `json:"value"`
}

// ParseHuaweiJSON consumes the records array incrementally. It never returns
// input text in errors and drops unsupported sensitive record families.
func ParseHuaweiJSON(reader io.Reader) (Result, error) {
	decoder := json.NewDecoder(io.LimitReader(reader, MaxInputBytes+1))
	decoder.UseNumber()
	if token, err := decoder.Token(); err != nil || token != json.Delim('{') {
		return Result{}, safeJSONError(err)
	}
	var result Result
	foundRecords := false
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return Result{}, safeJSONError(err)
		}
		key, ok := keyToken.(string)
		if !ok {
			return Result{}, &SafeError{Code: "source_schema_unsupported"}
		}
		if key != "records" {
			var discard json.RawMessage
			if err := decoder.Decode(&discard); err != nil {
				return Result{}, safeJSONError(err)
			}
			continue
		}
		foundRecords = true
		if token, err := decoder.Token(); err != nil || token != json.Delim('[') {
			return Result{}, &SafeError{Code: "source_schema_unsupported"}
		}
		for index := 0; decoder.More(); index++ {
			if index >= MaxRecordCount {
				return Result{}, &SafeError{Code: "json_token_too_large"}
			}
			var raw json.RawMessage
			if err := decoder.Decode(&raw); err != nil {
				return Result{}, safeJSONError(err)
			}
			if len(raw) > MaxRecordBytes {
				return Result{}, &SafeError{Code: "json_token_too_large"}
			}
			var record sourceRecord
			if err := json.Unmarshal(raw, &record); err != nil {
				return Result{}, &SafeError{Code: "source_schema_unsupported"}
			}
			sample, warning, err := normalizeRecord(record)
			if err != nil {
				return Result{}, err
			}
			if warning != nil {
				result.Warnings = append(result.Warnings, *warning)
			}
			if sample != nil {
				result.Samples = append(result.Samples, *sample)
			}
		}
		if token, err := decoder.Token(); err != nil || token != json.Delim(']') {
			return Result{}, safeJSONError(err)
		}
	}
	if token, err := decoder.Token(); err != nil || token != json.Delim('}') || !foundRecords {
		return Result{}, &SafeError{Code: "source_schema_unsupported"}
	}
	if decoder.More() {
		return Result{}, &SafeError{Code: "source_schema_unsupported"}
	}
	return result, nil
}

func normalizeRecord(record sourceRecord) (*Sample, *Warning, error) {
	if record.Type == "ecg" || record.Type == "workout_route" {
		return nil, &Warning{Code: "sensitive_record_excluded"}, nil
	}
	units := map[string]string{"heart_rate": "bpm", "steps": "count", "distance": "metres", "active_duration": "seconds"}
	wantUnit, supported := units[record.Type]
	if !supported {
		return nil, &Warning{Code: "metric_mapping_unknown"}, nil
	}
	if record.Unit != wantUnit || record.RecordID == "" {
		return nil, nil, &SafeError{Code: "unit_unsupported"}
	}
	start, err := time.Parse(time.RFC3339, record.StartedAt)
	if err != nil {
		return nil, nil, &SafeError{Code: "timestamp_invalid"}
	}
	end := start
	if record.EndedAt != "" {
		end, err = time.Parse(time.RFC3339, record.EndedAt)
		if err != nil || end.Before(start) {
			return nil, nil, &SafeError{Code: "timestamp_invalid"}
		}
	}
	value := strings.TrimSpace(string(record.Value))
	if value == "" || strings.HasPrefix(value, "\"") {
		return nil, nil, &SafeError{Code: "metric_mapping_unknown"}
	}
	recordHash := hash(record.RecordID)
	identity := strings.Join([]string{"v1", SourceFamily, record.Type, recordHash, start.UTC().Format(time.RFC3339Nano), end.UTC().Format(time.RFC3339Nano), wantUnit, value}, "|")
	return &Sample{SourceFamily: SourceFamily, SourceType: record.Type, SourceRecordHash: recordHash, StartedAt: start.UTC(), EndedAt: end.UTC(), Unit: wantUnit, Value: value, DedupeKey: hash(identity), ParserVersion: ParserVersion}, nil, nil
}

func hash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func safeJSONError(err error) error {
	if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
		return &SafeError{Code: "json_truncated"}
	}
	var syntax *json.SyntaxError
	if errors.As(err, &syntax) {
		return &SafeError{Code: "json_truncated"}
	}
	if err == nil {
		return &SafeError{Code: "source_schema_unsupported"}
	}
	return &SafeError{Code: "source_schema_unsupported"}
}

func SafeCode(err error) string {
	var safe *SafeError
	if errors.As(err, &safe) {
		return safe.Code
	}
	return fmt.Sprintf("%s", "source_schema_unsupported")
}
