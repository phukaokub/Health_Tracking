package normalization

import (
	"bytes"
	"encoding/binary"
	"os"
	"strings"
	"testing"

	"github.com/nkiri/xls"
)

func TestParseLegacyXLSSanitizedFixture(t *testing.T) {
	data, err := os.ReadFile("testdata/huawei_legacy_sanitized.xls")
	if err != nil {
		t.Fatal(err)
	}
	result, err := ParseLegacyXLS(bytes.NewReader(data), "Asia/Bangkok")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(result.Samples), 10; got != want {
		t.Fatalf("samples=%d want=%d", got, want)
	}
	if result.LegacyXLSQuality == nil ||
		result.LegacyXLSQuality.ApprovedSheetCount != 1 ||
		result.LegacyXLSQuality.ExcludedSheetCount != 1 ||
		result.LegacyXLSQuality.UnknownSheetCount != 1 ||
		result.LegacyXLSQuality.CoveredDateCount != 2 {
		t.Fatalf("unexpected quality summary: %#v", result.LegacyXLSQuality)
	}
	first := result.Samples[0]
	if first.StartedAt.Format("2006-01-02T15:04:05Z07:00") != "2026-01-13T17:00:00Z" ||
		first.CanonicalDay != "2026-01-14" ||
		first.TimezoneResolution != "import_timezone" {
		t.Fatalf("timezone normalization failed: %#v", first)
	}
	again, err := ParseLegacyXLS(bytes.NewReader(data), "Asia/Bangkok")
	if err != nil || again.Samples[0].DedupeKey != first.DedupeKey {
		t.Fatal("dedupe identity is not deterministic")
	}
}

func TestLegacyDailyIdentityExcludesConflictingCellValueAndFile(t *testing.T) {
	first := legacyDailyDedupeKey("steps", "2026-01-14", "Asia/Bangkok", "count")
	second := legacyDailyDedupeKey("steps", "2026-01-14", "Asia/Bangkok", "count")
	if first != second {
		t.Fatal("same owner metric day did not converge")
	}
	if first == legacyDailyDedupeKey("steps", "2026-01-15", "Asia/Bangkok", "count") {
		t.Fatal("different days collided")
	}
}

func TestParseLegacyXLSRejectsOversizedSharedStringDeclaration(t *testing.T) {
	data, err := os.ReadFile("testdata/huawei_legacy_sanitized.xls")
	if err != nil {
		t.Fatal(err)
	}
	changed := false
	for offset := 0; offset+12 <= len(data); offset++ {
		if data[offset] == 0xfc && data[offset+1] == 0x00 {
			length := int(binary.LittleEndian.Uint16(data[offset+2 : offset+4]))
			if length >= 8 && offset+4+length <= len(data) {
				binary.LittleEndian.PutUint32(data[offset+8:offset+12], maxLegacySSTEntries+1)
				changed = true
				break
			}
		}
	}
	if !changed {
		t.Fatal("fixture has no SST record")
	}
	_, err = ParseLegacyXLS(bytes.NewReader(data), "UTC")
	if SafeCode(err) != "xls_string_limit" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestParseLegacyXLSInputSizeBound(t *testing.T) {
	_, err := ParseLegacyXLS(bytes.NewReader(make([]byte, MaxLegacyXLSBytes+1)), "UTC")
	if SafeCode(err) != "xls_size_limit" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func BenchmarkParseLegacyXLSSanitized(b *testing.B) {
	data, err := os.ReadFile("testdata/huawei_legacy_sanitized.xls")
	if err != nil {
		b.Fatal(err)
	}
	b.ReportAllocs()
	b.SetBytes(int64(len(data)))
	for index := 0; index < b.N; index++ {
		if _, err := ParseLegacyXLS(bytes.NewReader(data), "Asia/Bangkok"); err != nil {
			b.Fatal(err)
		}
	}
}

func TestParseLegacyXLSRejectsMalformedAndInvalidTimezoneSafely(t *testing.T) {
	for _, test := range []struct {
		name string
		data []byte
		zone string
		code string
	}{
		{"malformed", []byte("not a workbook"), "UTC", "xls_malformed"},
		{"timezone", make([]byte, 512), "Private/Identifier", "timezone_invalid"},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, err := ParseLegacyXLS(bytes.NewReader(test.data), test.zone)
			if SafeCode(err) != test.code || strings.Contains(err.Error(), string(test.data)) {
				t.Fatalf("unsafe or wrong error: %v", err)
			}
		})
	}
}

func TestLegacyXLSFixturePrivacyContract(t *testing.T) {
	data, err := os.ReadFile("testdata/huawei_legacy_sanitized.xls")
	if err != nil {
		t.Fatal(err)
	}
	book, err := xls.Read(bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	var visible strings.Builder
	for _, sheet := range book.Sheets {
		visible.WriteString(sheet.Name())
		for _, row := range sheet.Strings() {
			visible.WriteString(strings.Join(row, " "))
		}
	}
	lower := strings.ToLower(visible.String())
	for _, forbidden := range []string{"@", "password", "token", "latitude", "longitude", "ecg", "rri", "route"} {
		if strings.Contains(lower, forbidden) {
			t.Fatalf("fixture contains forbidden marker %q", forbidden)
		}
	}
}
