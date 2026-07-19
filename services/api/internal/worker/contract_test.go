package worker

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestCheckpointRejectsStaleGenerationAndUnsafeFields(t *testing.T) {
	lease := Lease{JobID: "job", ImportID: "import", Generation: "generation"}
	checkpoint := Checkpoint{JobID: "job", ImportID: "import", ImportFileID: "file", LeaseGeneration: "stale", PartIndex: 0, BatchSequence: 1}
	if err := checkpoint.Validate(lease); err == nil {
		t.Fatal("stale lease generation was accepted")
	}
	checkpoint.LeaseGeneration = lease.Generation
	checkpoint.WarningCodes = []string{"contains-payload"}
	if err := checkpoint.Validate(lease); err == nil {
		t.Fatal("unsafe warning code was accepted")
	}
}

func TestProgressContractIsPrivacySafe(t *testing.T) {
	encoded, err := json.Marshal(Progress{ProcessedFileCount: 1, TotalFileCount: 2, NormalizedRecordCount: 4, WarningCodes: []string{"route_content_dropped"}, State: "processing"})
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"payload", "path", "email", "waveform", "latitude", "longitude", "credential", "token"} {
		if strings.Contains(string(encoded), forbidden) {
			t.Fatalf("forbidden field %q present: %s", forbidden, encoded)
		}
	}
}

func TestCheckpointValidationBoundsReplayMetadata(t *testing.T) {
	lease := Lease{JobID: "job", ImportID: "import", Generation: "generation"}
	checkpoint := Checkpoint{JobID: "job", ImportID: "import", ImportFileID: "file", LeaseGeneration: "generation", PartIndex: 0, ByteOffset: 0, BatchSequence: 0, NormalizedRecordCount: 1}
	if err := checkpoint.Validate(lease); err != nil {
		t.Fatal(err)
	}
	checkpoint.ByteOffset = -1
	if err := checkpoint.Validate(lease); err == nil {
		t.Fatal("negative byte offset was accepted")
	}
}

func TestRawPartsCleanupRequiresElapsedWindowAndNoLease(t *testing.T) {
	now := time.Unix(1000, 0)
	if ShouldCleanupRawParts(now, now.Add(RawPartsRecoveryWindow), true, false) {
		t.Fatal("cleanup crossed the recovery window")
	}
	if !ShouldCleanupRawParts(now.Add(RawPartsRecoveryWindow), now.Add(RawPartsRecoveryWindow), true, false) {
		t.Fatal("eligible cleanup was rejected")
	}
	if ShouldCleanupRawParts(now.Add(2*RawPartsRecoveryWindow), now, true, true) {
		t.Fatal("cleanup ignored an active lease")
	}
}

func TestProgressRejectsImpossibleCounts(t *testing.T) {
	if err := (Progress{ProcessedFileCount: 2, TotalFileCount: 1}).Validate(); err == nil {
		t.Fatal("processed files exceeded total")
	}
}
