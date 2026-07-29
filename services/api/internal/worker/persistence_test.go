package worker

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"testing"
)

type memoryParts map[string][]byte

func (parts memoryParts) OpenPart(_ context.Context, path string) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader(parts[path])), nil
}

func TestParsePrivatePartsVerifiesPartsAndExcludesSensitiveFamilies(t *testing.T) {
	data := []byte(`{"records":[{"type":"heart_rate","record_id":"synthetic-heart","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72},{"type":"ecg","record_id":"synthetic-ecg","started_at":"2026-01-02T03:04:05Z"},{"type":"workout_route","record_id":"synthetic-route","started_at":"2026-01-02T03:04:05Z"}]}`)
	sum := sha256.Sum256(data)
	result, err := ParsePrivateParts(context.Background(), memoryParts{"safe": data}, []SourcePart{{Index: 0, Bytes: int64(len(data)), SHA256: hex.EncodeToString(sum[:]), Path: "safe"}})
	if err != nil || len(result.Samples) != 1 || len(result.Warnings) != 2 {
		t.Fatalf("unexpected privacy-safe parse: %#v, %v", result, err)
	}
	records := CanonicalRecords(result)
	if len(records) != 1 || records[0]["kind"] != "sample" {
		t.Fatalf("sensitive records reached canonical contract: %#v", records)
	}
}

func TestParsePrivatePartsRejectsDigestMismatchWithoutReturningSource(t *testing.T) {
	_, err := ParsePrivateParts(context.Background(), memoryParts{"safe": []byte(`{"records":[]}`)}, []SourcePart{{Index: 0, Bytes: 14, SHA256: "0000000000000000000000000000000000000000000000000000000000000000", Path: "safe"}})
	if err == nil || err.Error() != "source_part_invalid" {
		t.Fatalf("expected safe digest failure, got %v", err)
	}
}
