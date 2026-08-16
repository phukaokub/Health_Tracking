package normalization

import (
	"bytes"
	"encoding/json"
	"io"
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

func TestParseHuaweiJSONMapsApprovedScalarMetricsAndUnits(t *testing.T) {
	input := `{"records":[{"type":"resting_heart_rate","record_id":"rhr","started_at":"2026-01-02T00:00:00Z","unit":"bpm","value":60},{"type":"hrv","record_id":"hrv","started_at":"2026-01-02T00:00:00Z","unit":"ms","value":24},{"type":"skin_temperature","record_id":"temp","started_at":"2026-01-02T00:00:00Z","unit":"fahrenheit","value":98.6},{"type":"spo2","record_id":"spo2","started_at":"2026-01-02T00:00:00Z","unit":"fraction","value":0.98},{"type":"calories","record_id":"energy","started_at":"2026-01-02T00:00:00Z","unit":"kj","value":4.184}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Samples) != 5 {
		t.Fatalf("want five samples, got %#v", result)
	}
	if result.Samples[2].Unit != "degrees_celsius" || result.Samples[2].Value != "37" || result.Samples[3].Value != "98" || result.Samples[4].Unit != "kilocalories" || result.Samples[4].Value != "1" {
		t.Fatalf("unexpected conversions: %#v", result.Samples)
	}
	if result.Samples[2].SourceUnit != "fahrenheit" || result.Samples[2].UnitConversionVersion != "v1" {
		t.Fatal("source unit provenance missing")
	}
}

func TestParseHuaweiJSONMapsSleepWithoutRawStagePayload(t *testing.T) {
	input := `{"records":[{"type":"sleep_session","record_id":"synthetic-sleep","started_at":"2026-01-02T00:00:00Z","ended_at":"2026-01-02T08:00:00Z","stages":[{"code":"deep","started_at":"2026-01-02T00:00:00Z","ended_at":"2026-01-02T01:00:00Z"},{"code":"light","started_at":"2026-01-02T01:00:00Z","ended_at":"2026-01-02T08:00:00Z"}]}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.SleepSessions) != 1 || len(result.SleepSessions[0].Stages) != 2 || result.SleepSessions[0].DurationSeconds != 28800 {
		t.Fatalf("unexpected sleep output: %#v", result)
	}
	encoded, _ := json.Marshal(result)
	if strings.Contains(string(encoded), "synthetic-sleep") {
		t.Fatalf("raw sleep ID escaped: %s", encoded)
	}
}

func TestParseHuaweiJSONMapsActivityWithoutRoute(t *testing.T) {
	input := `{"records":[{"type":"activity","record_id":"synthetic-activity","activity_type":"walking","started_at":"2026-01-02T00:00:00Z","ended_at":"2026-01-02T00:10:00Z","route":[{"lat":0,"lon":0}]}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Activities) != 1 || result.Activities[0].DurationSeconds != 600 {
		t.Fatalf("unexpected activity: %#v", result)
	}
	encoded, _ := json.Marshal(result)
	if strings.Contains(string(encoded), "route") || strings.Contains(string(encoded), "synthetic-activity") {
		t.Fatalf("raw activity content escaped: %s", encoded)
	}
}

func TestParseHuaweiJSONMapsWorkoutSummaryWithoutRoute(t *testing.T) {
	input := `{"records":[{"type":"workout_summary","record_id":"synthetic-workout","workout_type":"running","started_at":"2026-01-02T00:00:00Z","ended_at":"2026-01-02T00:30:00Z","distance_metres":5000,"energy_kilocalories":300,"route":[{"lat":0,"lon":0}]}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Workouts) != 1 || result.Workouts[0].DistanceMetres != "5000" || result.Workouts[0].EnergyKilocalories != "300" {
		t.Fatalf("unexpected workout: %#v", result)
	}
	encoded, _ := json.Marshal(result)
	if strings.Contains(string(encoded), "route") || strings.Contains(string(encoded), "synthetic-workout") {
		t.Fatalf("raw workout content escaped: %s", encoded)
	}
}

func TestParseHuaweiJSONMapsHuaweiActivityExportArrayWithoutRouteData(t *testing.T) {
	input := `[{"sportType":4,"startTime":1767315845000,"totalTime":1800000,"totalDistance":5000,"totalCalories":3000,"timeZone":"+0700","attribute":"HW_EXT_TRACK_DETAIL@is{\"route\":[{\"lat\":0,\"lon\":0}]}&&HW_EXT_TRACK_SIMPLIFY@is{\"totalDistance\":5000,\"totalCalories\":3000}"}]`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Workouts) != 1 {
		t.Fatalf("expected one Huawei activity, got %#v", result)
	}
	workout := result.Workouts[0]
	if workout.WorkoutType != "running" || workout.DurationSeconds != 1800 || workout.DistanceMetres != "5000" || workout.EnergyKilocalories != "3" {
		t.Fatalf("unexpected Huawei activity summary: %#v", workout)
	}
	encoded, _ := json.Marshal(result)
	if strings.Contains(string(encoded), "route") || strings.Contains(string(encoded), "lat") || strings.Contains(string(encoded), "attribute") {
		t.Fatalf("raw Huawei detail escaped: %s", encoded)
	}
}

func TestParseHuaweiJSONAllowsBoundedLargeHuaweiActivityDetail(t *testing.T) {
	input := `[{"sportType":4,"startTime":1767315845000,"totalTime":1800000,"attribute":"` + strings.Repeat("x", MaxRecordBytes+1) + `"}]`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Workouts) != 1 || result.Workouts[0].WorkoutType != "running" {
		t.Fatalf("expected canonical activity summary, got %#v", result)
	}
}

func TestParseHuaweiJSONAllowsBoundedLargeInternalActivityDetail(t *testing.T) {
	input := `{"records":[{"type":"activity","record_id":"large-activity","activity_type":"walking","started_at":"2026-01-02T00:00:00Z","ended_at":"2026-01-02T00:10:00Z","route":"` + strings.Repeat("x", MaxRecordBytes+1) + `"}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Activities) != 1 || result.Activities[0].DurationSeconds != 600 {
		t.Fatalf("expected canonical activity summary, got %#v", result)
	}
}

func TestParseHuaweiJSONMapsNestedHuaweiActivityExportArray(t *testing.T) {
	input := `[{"recordDay":20260102,"motionPathData":[{"sportType":5,"startTime":1767315845000,"totalTime":600000}]}]`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Workouts) != 1 || result.Workouts[0].WorkoutType != "walking" {
		t.Fatalf("unexpected nested Huawei activity: %#v", result)
	}
}

func TestParseHuaweiJSONAllowsBoundedLargeNestedHuaweiHealthRecord(t *testing.T) {
	input := `{"motionPathData":[{"type":7,"samplePoints":[],"boundedMetadata":"` + strings.Repeat("x", MaxRecordBytes+1) + `"}]}`
	if _, err := ParseHuaweiJSON(strings.NewReader(input)); err != nil {
		t.Fatalf("large nested Huawei Health record should remain within its bounded limit: %v", err)
	}
}

func TestParseHuaweiJSONExcludesOversizedNestedHuaweiDetail(t *testing.T) {
	input := `[{"recordDay":20260102,"motionPathData":[{"routeData":"` + strings.Repeat("x", MaxRecordBytes+1) + `"}]}]`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Code != "source_detail_excluded" {
		t.Fatalf("expected oversized nested detail warning, got %#v", result.Warnings)
	}
}

func TestParseHuaweiJSONExcludesOversizedHuaweiActivityItem(t *testing.T) {
	input := `[{"unrecognizedDetail":"` + strings.Repeat("x", MaxRecordBytes+1) + `"}]`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Code != "source_detail_excluded" {
		t.Fatalf("expected oversized activity-item warning, got %#v", result.Warnings)
	}
}

func TestParseHuaweiJSONMapsWrappedHuaweiActivityExportArray(t *testing.T) {
	input := `{"motionPathData":[{"sportType":"4","startTime":1767315845000,"totalTime":1800000,"totalDistance":5000}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Workouts) != 1 || result.Workouts[0].WorkoutType != "running" {
		t.Fatalf("unexpected wrapped Huawei activity: %#v", result)
	}
}

func TestParseHuaweiJSONMapsHuaweiHealthSamplePointExport(t *testing.T) {
	input := `[{"type":7,"recordId":"health-record","samplePoints":[{"startTime":1767315845000,"endTime":1767315905000,"value":"78.0","key":"DATA_POINT_DYNAMIC_HEARTRATE"},{"startTime":1767315845000,"value":"120","key":"DATA_POINT_STEP_COUNT"}]}]`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Samples) != 2 {
		t.Fatalf("expected two Huawei samples, got %#v", result)
	}
	if result.Samples[0].SourceType != "heart_rate" || result.Samples[0].Unit != "bpm" || result.Samples[0].Value != "78" {
		t.Fatalf("unexpected heart-rate sample: %#v", result.Samples[0])
	}
	if result.Samples[1].SourceType != "steps" || result.Samples[1].Unit != "count" || result.Samples[1].Value != "120" {
		t.Fatalf("unexpected steps sample: %#v", result.Samples[1])
	}
}

func TestParseHuaweiJSONAllowsLargeTopLevelHuaweiHealthArray(t *testing.T) {
	record := `{"type":7,"recordId":"health-record","samplePoints":[{"startTime":1767315845000,"value":"120","key":"DATA_POINT_STEP_COUNT"}]}`
	recordCount := MaxHuaweiHealthRecordCount - 1
	input := "[" + strings.TrimSuffix(strings.Repeat(record+",", recordCount), ",") + "]"
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatalf("large top-level Huawei Health array should remain bounded and parse: %v", err)
	}
	if len(result.Samples) != recordCount {
		t.Fatalf("expected %d samples, got %d", recordCount, len(result.Samples))
	}
}

func TestParseHuaweiJSONAllowsBoundedLargeHuaweiHealthRecord(t *testing.T) {
	input := `[{"type":7,"samplePoints":[],"boundedMetadata":"` + strings.Repeat("x", MaxRecordBytes+1) + `"}]`
	if _, err := ParseHuaweiJSON(strings.NewReader(input)); err != nil {
		t.Fatalf("large Huawei Health record should remain within its bounded limit: %v", err)
	}
}

func TestRepairMotionMapDecimalKeysIsNarrowAndStrict(t *testing.T) {
	repaired, err := RepairMotionMapDecimalKeys([]byte(`{"paceMap":{1.5:12,"2.0":20}}`))
	if err != nil || string(repaired) != `{"paceMap":{"1.5":12,"2.0":20}}` {
		t.Fatalf("unexpected repair: %q %v", repaired, err)
	}
	_, err = RepairMotionMapDecimalKeys([]byte(`{"other":{1.5:12}}`))
	if SafeCode(err) != "motion_repair_out_of_scope" {
		t.Fatalf("expected narrow failure, got %v", err)
	}
	_, err = RepairMotionMapDecimalKeys([]byte(`{"paceMap":{1.5:}}`))
	if SafeCode(err) != "motion_json_invalid" {
		t.Fatalf("expected strict validation failure, got %v", err)
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

func TestParseHuaweiJSONExcludesOversizedUnknownInternalRecord(t *testing.T) {
	input := `{"records":[{"type":"provider_blob","detail":"` + strings.Repeat("x", MaxRecordBytes+1) + `"}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Code != "source_detail_excluded" {
		t.Fatalf("expected oversized unknown-record warning, got %#v", result.Warnings)
	}
}

func TestParseHuaweiJSONExcludesOversizedKnownRecordDetail(t *testing.T) {
	input := `{"records":[{"type":"heart_rate","record_id":"detail","value":[` + strings.Repeat("1,", 600000) + `1]}]}`
	result, err := ParseHuaweiJSON(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Code != "source_detail_excluded" {
		t.Fatalf("expected oversized known-detail warning, got %#v", result.Warnings)
	}
}

type oneByteReader struct{ data []byte }

func (reader *oneByteReader) Read(target []byte) (int, error) {
	if len(reader.data) == 0 {
		return 0, io.EOF
	}
	target[0] = reader.data[0]
	reader.data = reader.data[1:]
	return 1, nil
}

func TestParseHuaweiJSONIsChunkInvariant(t *testing.T) {
	input := []byte(`{"records":[{"type":"heart_rate","record_id":"synthetic-chunk","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72}]}`)
	whole, err := ParseHuaweiJSON(bytes.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	chunked, err := ParseHuaweiJSON(&oneByteReader{data: append([]byte(nil), input...)})
	if err != nil {
		t.Fatal(err)
	}
	wholeJSON, _ := json.Marshal(whole)
	chunkedJSON, _ := json.Marshal(chunked)
	if string(wholeJSON) != string(chunkedJSON) {
		t.Fatalf("chunking changed output: %s != %s", wholeJSON, chunkedJSON)
	}
}

func FuzzParseHuaweiJSON(f *testing.F) {
	f.Add([]byte(`{"records":[]}`))
	f.Add([]byte(`{"records":[{"type":"heart_rate","record_id":"synthetic-fuzz","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72}]}`))
	f.Add([]byte(`{"records":[`))
	f.Fuzz(func(t *testing.T, input []byte) {
		_, _ = ParseHuaweiJSON(bytes.NewReader(input))
	})
}
