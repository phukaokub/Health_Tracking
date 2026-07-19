// Package worker contains provider-independent contracts for bounded parser
// execution. It never accepts source payloads, credentials, or owner-supplied
// paths; adapters bind these values to the leased import in the database.
package worker

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"time"
)

const (
	ParserVersion          = "huawei-json-v1"
	LeaseDuration          = 240 * time.Second
	RawPartsRecoveryWindow = 24 * time.Hour
	MaxAttempts            = 3
	MaxBatchRows           = 1000
	MaxWarningCodes        = 32
	MaxParserVersionLength = 64
)

var safeCode = regexp.MustCompile(`^[a-z0-9_]{3,80}$`)

// Lease is the server-authoritative identity of one worker claim.
type Lease struct {
	JobID         string    `json:"job_id"`
	ImportID      string    `json:"import_id"`
	UserID        string    `json:"user_id"`
	WorkerSubject string    `json:"worker_subject"`
	Generation    string    `json:"lease_generation"`
	ExpiresAt     time.Time `json:"lease_expires_at"`
	Attempt       int       `json:"attempt_count"`
	ParserVersion string    `json:"parser_version"`
}

// Checkpoint is a replay-safe token boundary. ByteOffset is metadata only; no
// token text or source excerpt is retained.
type Checkpoint struct {
	JobID                 string   `json:"job_id"`
	ImportID              string   `json:"import_id"`
	ImportFileID          string   `json:"import_file_id"`
	LeaseGeneration       string   `json:"lease_generation"`
	PartIndex             int      `json:"part_index"`
	ByteOffset            int64    `json:"byte_offset"`
	BatchSequence         int      `json:"batch_sequence"`
	NormalizedRecordCount int64    `json:"normalized_record_count"`
	WarningCodes          []string `json:"warning_codes,omitempty"`
}

// Progress is safe for owner-visible responses: counts and stable codes only.
type Progress struct {
	ProcessedFileCount    int      `json:"processed_file_count"`
	TotalFileCount        int      `json:"total_file_count"`
	NormalizedRecordCount int64    `json:"normalized_record_count"`
	WarningCodes          []string `json:"warning_codes,omitempty"`
	State                 string   `json:"state"`
}

func (checkpoint Checkpoint) Validate(lease Lease) error {
	if checkpoint.JobID != lease.JobID || checkpoint.ImportID != lease.ImportID || checkpoint.LeaseGeneration != lease.Generation {
		return errors.New("checkpoint lease mismatch")
	}
	if checkpoint.ImportFileID == "" || checkpoint.PartIndex < 0 || checkpoint.ByteOffset < 0 || checkpoint.BatchSequence < 0 {
		return errors.New("checkpoint position is invalid")
	}
	if checkpoint.NormalizedRecordCount < 0 || len(checkpoint.WarningCodes) > MaxWarningCodes {
		return errors.New("checkpoint counts or warnings are invalid")
	}
	for _, code := range checkpoint.WarningCodes {
		if !safeCode.MatchString(code) {
			return fmt.Errorf("warning code is not safe: %q", code)
		}
	}
	return nil
}

func (progress Progress) Validate() error {
	if progress.ProcessedFileCount < 0 || progress.TotalFileCount < 0 || progress.ProcessedFileCount > progress.TotalFileCount {
		return errors.New("progress file counts are invalid")
	}
	if progress.NormalizedRecordCount < 0 || len(progress.WarningCodes) > MaxWarningCodes {
		return errors.New("progress counts or warnings are invalid")
	}
	for _, code := range progress.WarningCodes {
		if !safeCode.MatchString(code) {
			return fmt.Errorf("warning code is not safe: %q", code)
		}
	}
	return nil
}

// ShouldCleanupRawParts is intentionally pure so local tests can prove the
// 24-hour recovery gate without touching Storage or a hosted provider.
func ShouldCleanupRawParts(now, recoveryUntil time.Time, terminal bool, activeLease bool) bool {
	return terminal && !activeLease && !recoveryUntil.IsZero() && !now.Before(recoveryUntil)
}

func (progress Progress) MarshalJSON() ([]byte, error) {
	if err := progress.Validate(); err != nil {
		return nil, err
	}
	type alias Progress
	return json.Marshal(alias(progress))
}
