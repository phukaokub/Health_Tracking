package worker

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"testing"
	"time"

	"github.com/phukaokub/Health_Tracking/services/api/internal/normalization"
)

func TestParsePrivatePartsDispatchesLegacyXLS(t *testing.T) {
	data, err := os.ReadFile("../normalization/testdata/huawei_legacy_sanitized.xls")
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	result, err := ParsePrivatePartsForSource(context.Background(), memoryParts{"safe": data}, []SourcePart{{
		Index: 0, Bytes: int64(len(data)), SHA256: hex.EncodeToString(sum[:]), Path: "safe",
	}}, "legacy-xls", "Asia/Bangkok")
	if err != nil {
		t.Fatal(err)
	}
	if result.LegacyXLSQuality == nil || len(result.Samples) != 10 {
		t.Fatalf("unexpected XLS result: %#v", result.LegacyXLSQuality)
	}
	for _, record := range CanonicalRecords(result) {
		for _, forbidden := range []string{"raw", "route", "ecg", "rri", "gps"} {
			if _, exists := record[forbidden]; exists {
				t.Fatalf("canonical record contains %q", forbidden)
			}
		}
	}
}

type memoryParts map[string][]byte

func (parts memoryParts) OpenPart(_ context.Context, path string) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader(parts[path])), nil
}

func TestParsePrivatePartsVerifiesPartsAndExcludesSensitiveFamilies(t *testing.T) {
	data := []byte(`{"records":[{"type":"heart_rate","record_id":"synthetic-heart","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72},{"type":"ecg","record_id":"synthetic-ecg","started_at":"2026-01-02T03:04:05Z"},{"type":"workout_route","record_id":"synthetic-route","started_at":"2026-01-02T03:04:05Z"}]}`)
	sum := sha256.Sum256(data)
	result, err := ParsePrivateParts(context.Background(), memoryParts{"safe": data}, []SourcePart{{Index: 0, Bytes: int64(len(data)), SHA256: hex.EncodeToString(sum[:]), Path: "safe"}})
	if err != nil || len(result.Samples) != 1 || len(result.Warnings) != 1 {
		t.Fatalf("unexpected privacy-safe parse: %#v, %v", result, err)
	}
	records := CanonicalRecords(result)
	if len(records) != 1 || records[0]["kind"] != "sample" {
		t.Fatalf("sensitive records reached canonical contract: %#v", records)
	}
}

func TestCanonicalRecordsCarryDailyGroupingAndNestedWorkoutData(t *testing.T) {
	result := normalization.Result{
		Samples: []normalization.Sample{{
			SourceFamily: "huawei_health_json", SourceType: "steps", SourceRecordHash: "hash",
			StartedAt: time.Date(2026, 1, 1, 23, 30, 0, 0, time.UTC), EndedAt: time.Date(2026, 1, 1, 23, 31, 0, 0, time.UTC),
			Unit: "count", SourceUnit: "count", Value: "12", DedupeKey: "dedupe", ParserVersion: normalization.ParserVersion,
		}},
		Workouts: []normalization.Workout{{
			SourceRecordHash: "workout-hash", WorkoutType: "walking", StartedAt: time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC), EndedAt: time.Date(2026, 1, 2, 0, 1, 0, 0, time.UTC),
			DurationSeconds: 60, DistanceMetres: "80", EnergyKilocalories: "3", DedupeKey: "workout-dedupe", ParserVersion: normalization.ParserVersion,
		}},
	}
	normalization.AssignCanonicalDays(&result, "Asia/Bangkok")
	records := CanonicalRecords(result)
	if records[0]["canonical_day"] != "2026-01-02" || records[0]["timezone_resolution"] != "import_timezone" {
		t.Fatalf("daily grouping fields missing: %#v", records[0])
	}
	if records[1]["kind"] != "workout" || records[1]["distance_metres"] != "80" || records[1]["energy_kilocalories"] != "3" {
		t.Fatalf("nested workout fields missing: %#v", records[1])
	}
}

func TestParsePrivatePartsRejectsDigestMismatchWithoutReturningSource(t *testing.T) {
	_, err := ParsePrivateParts(context.Background(), memoryParts{"safe": []byte(`{"records":[]}`)}, []SourcePart{{Index: 0, Bytes: 14, SHA256: "0000000000000000000000000000000000000000000000000000000000000000", Path: "safe"}})
	if err == nil || err.Error() != "source_part_invalid" {
		t.Fatalf("expected safe digest failure, got %v", err)
	}
}
