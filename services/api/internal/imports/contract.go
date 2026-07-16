// Package imports defines the metadata-only contract for Step 3 import flows.
// It deliberately has no file-content fields: source bytes upload directly from
// the browser to private Supabase Storage.
package imports

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
)

const (
	ManifestVersion          = 1
	MaxManifestBytes         = 1 * 1024 * 1024
	MaxLogicalPartBytes      = 20 * 1024 * 1024
	TUSTransportChunkBytes   = 6 * 1024 * 1024
	MaxManifestPageFileCount = 1000
)

var (
	sha256Pattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
	uuidPattern   = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
)

type SourceKind string

const (
	SourceKindDirectory SourceKind = "directory"
	SourceKindZIP       SourceKind = "zip"
)

type ImportState string

const (
	ImportStateDraft                 ImportState = "draft"
	ImportStateUploading             ImportState = "uploading"
	ImportStateUploaded              ImportState = "uploaded"
	ImportStateQueued                ImportState = "queued"
	ImportStateProcessing            ImportState = "processing"
	ImportStateCompleted             ImportState = "completed"
	ImportStateCompletedWithWarnings ImportState = "completed_with_warnings"
	ImportStateFailed                ImportState = "failed"
	ImportStateCancelling            ImportState = "cancelling"
	ImportStateCancelled             ImportState = "cancelled"
	ImportStateDeleting              ImportState = "deleting"
	ImportStateDeleted               ImportState = "deleted"
)

var allowedTransitions = map[ImportState]map[ImportState]bool{
	ImportStateDraft: {
		ImportStateUploading:  true,
		ImportStateCancelling: true,
	},
	ImportStateUploading: {
		ImportStateUploaded:   true,
		ImportStateFailed:     true,
		ImportStateCancelling: true,
	},
	ImportStateUploaded: {
		ImportStateQueued:     true,
		ImportStateFailed:     true,
		ImportStateCancelling: true,
	},
	ImportStateQueued: {
		ImportStateProcessing: true,
		ImportStateFailed:     true,
		ImportStateCancelling: true,
	},
	ImportStateProcessing: {
		ImportStateCompleted:             true,
		ImportStateCompletedWithWarnings: true,
		ImportStateFailed:                true,
		ImportStateCancelling:            true,
	},
	ImportStateCompleted:             {ImportStateDeleting: true},
	ImportStateCompletedWithWarnings: {ImportStateDeleting: true},
	ImportStateFailed:                {ImportStateDeleting: true},
	ImportStateCancelling:            {ImportStateCancelled: true},
	ImportStateCancelled:             {ImportStateDeleting: true},
	ImportStateDeleting:              {ImportStateDeleted: true},
}

// CanTransitionTo reports whether a server-authoritative import state change is valid.
func (state ImportState) CanTransitionTo(next ImportState) bool {
	return allowedTransitions[state][next]
}

// CreateRequest is the bounded first page of an import manifest. It contains no
// absolute or relative source path, account data, or health content.
type CreateRequest struct {
	ManifestVersion      int
	SourceKind           SourceKind
	ClientIdempotencyKey string
	TimezoneCandidate    string
	TotalFileCount       int
	TotalLogicalBytes    int64
}

func (request CreateRequest) Validate() error {
	if request.ManifestVersion != ManifestVersion {
		return fmt.Errorf("manifest_version must be %d", ManifestVersion)
	}
	if request.SourceKind != SourceKindDirectory && request.SourceKind != SourceKindZIP {
		return errors.New("source_kind must be directory or zip")
	}
	if !isUUID(request.ClientIdempotencyKey) {
		return errors.New("client_idempotency_key must be a UUID")
	}
	if len(request.TimezoneCandidate) > 64 {
		return errors.New("timezone_candidate must be 64 characters or fewer")
	}
	if request.TotalFileCount < 0 || request.TotalFileCount > MaxManifestPageFileCount {
		return fmt.Errorf("total_file_count must be between 0 and %d", MaxManifestPageFileCount)
	}
	if request.TotalLogicalBytes < 0 {
		return errors.New("total_logical_bytes must not be negative")
	}
	return nil
}

// FileDescriptor is metadata for one logical file. SourceReferenceHash is a
// SHA-256 of a normalized source reference; raw paths are not accepted here.
type FileDescriptor struct {
	ClientFileID        string
	SourceReferenceHash string
	SourceFamily        string
	ContentKind         string
	LogicalBytes        int64
	ContentSHA256       string
}

func (file FileDescriptor) Validate() error {
	if !isUUID(file.ClientFileID) {
		return errors.New("client_file_id must be a UUID")
	}
	if !isSHA256(file.SourceReferenceHash) || !isSHA256(file.ContentSHA256) {
		return errors.New("source_reference_hash and content_sha256 must be lowercase SHA-256 values")
	}
	if len(file.SourceFamily) == 0 || len(file.SourceFamily) > 64 {
		return errors.New("source_family must contain 1 to 64 characters")
	}
	if len(file.ContentKind) == 0 || len(file.ContentKind) > 128 {
		return errors.New("content_kind must contain 1 to 128 characters")
	}
	if file.LogicalBytes < 0 {
		return errors.New("logical_bytes must not be negative")
	}
	return nil
}

// PartDescriptor describes an immutable logical Storage object. TUS divides this
// logical object into transport chunks; it does not change ByteLength.
type PartDescriptor struct {
	PartIndex     int
	ByteOffset    int64
	ByteLength    int
	ContentSHA256 string
	ObjectPath    string
}

func (part PartDescriptor) Validate(userID, importID, fileID string) error {
	if !isUUID(userID) || !isUUID(importID) || !isUUID(fileID) {
		return errors.New("owner, import, and file IDs must be UUIDs")
	}
	if part.PartIndex < 0 || part.ByteOffset < 0 {
		return errors.New("part_index and byte_offset must not be negative")
	}
	if part.ByteLength < 1 || part.ByteLength > MaxLogicalPartBytes {
		return fmt.Errorf("byte_length must be between 1 and %d", MaxLogicalPartBytes)
	}
	if !isSHA256(part.ContentSHA256) {
		return errors.New("content_sha256 must be a lowercase SHA-256 value")
	}
	if part.ObjectPath != ObjectPath(userID, importID, fileID, part.PartIndex) {
		return errors.New("object_path does not match the immutable owner/import/file path")
	}
	return nil
}

func ObjectPath(userID, importID, fileID string, partIndex int) string {
	return fmt.Sprintf("imports/%s/%s/%s/part-%d", strings.ToLower(userID), strings.ToLower(importID), strings.ToLower(fileID), partIndex)
}

func isSHA256(value string) bool {
	return sha256Pattern.MatchString(value)
}

func isUUID(value string) bool {
	return uuidPattern.MatchString(strings.ToLower(value))
}
