package normalization

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"
)

func TestParseHuaweiJSONIsDeterministicAndExcludesSensitiveRecords(t *testing.T) {
	fixture, err := os.ReadFile("testdata/huawei_sanitized.json")
	if err != nil {
		t.Fatal(err)
	}
	first, err := ParseHuaweiJSON(bytes.NewReader(fixture))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	second, err := ParseHuaweiJSON(bytes.NewReader(fixture))
	if err != nil {
		t.Fatalf("second parse: %v", err)
	}
	firstJSON, _ := json.Marshal(first)
	secondJSON, _ := json.Marshal(second)
	if string(firstJSON) != string(secondJSON) {
		t.Fatal("normalization was not deterministic")
	}
	if len(first.Samples) != 2 || len(first.Warnings) != 2 {
		t.Fatalf("unexpected output: %#v", first)
	}
	if first.Samples[0].DedupeKey == "" || first.Samples[0].SourceRecordHash == "" {
		t.Fatal("provenance hashes missing")
	}
	if strings.Contains(string(firstJSON), "waveform") || strings.Contains(string(firstJSON), "route") || strings.Contains(string(firstJSON), "synthetic-ecg-a") {
		t.Fatalf("sensitive or raw source data escaped: %s", firstJSON)
	}
}

func TestParseHuaweiJSONCollapsesDuplicateIdentity(t *testing.T) {
	input := `{"records":[{"type":"heart_rate","record_id":"synthetic-a","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72},{"type":"heart_rate","record_id":"synthetic-a","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Samples) != 2 || result.Samples[0].DedupeKey != result.Samples[1].DedupeKey {
		t.Fatalf("duplicate identity not stable: %#v", result.Samples)
	}
}

func TestParseHuaweiJSONReturnsSafeMalformedCodes(t *testing.T) {
	for _, input := range []string{"{\"records\":[", `{"records":{}}`, `{"records":[{"type":"heart_rate","record_id":"x","started_at":"bad","unit":"bpm","value":72}]}`} {
		_, err := ParseHuaweiJSON(strings.NewReader(input))
		if err == nil {
			t.Fatal("invalid input accepted")
		}
		code := SafeCode(err)
		if strings.Contains(code, "x") || strings.Contains(code, "bad") {
			t.Fatalf("unsafe error code: %q", code)
		}
	}
}

func TestParseHuaweiJSONRejectsOversizedRecord(t *testing.T) {
	input := `{"records":[{"type":"heart_rate","record_id":"x","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":` + strings.Repeat("1", MaxRecordBytes+1) + `}]}`
	_, err := ParseHuaweiJSON(strings.NewReader(input))
	if SafeCode(err) != "json_token_too_large" {
		t.Fatalf("expected bounded error, got %v", err)
	}
}
