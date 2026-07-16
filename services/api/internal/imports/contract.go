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
	MaxManifestFileCount     = 5000
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
	ManifestVersion      int        `json:"manifest_version"`
	SourceKind           SourceKind `json:"source_kind"`
	ClientIdempotencyKey string     `json:"client_idempotency_key"`
	TimezoneCandidate    string     `json:"timezone_candidate,omitempty"`
	TotalFileCount       int        `json:"total_file_count"`
	TotalLogicalBytes    int64      `json:"total_logical_bytes"`
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
	if request.TotalFileCount < 0 || request.TotalFileCount > MaxManifestFileCount {
		return fmt.Errorf("total_file_count must be between 0 and %d", MaxManifestFileCount)
	}
	if request.TotalLogicalBytes < 0 {
		return errors.New("total_logical_bytes must not be negative")
	}
	return nil
}

// FileDescriptor is metadata for one logical file. SourceReferenceHash is a
// SHA-256 of a normalized source reference; raw paths are not accepted here.
type FileDescriptor struct {
	ClientFileID        string `json:"client_file_id"`
	SourceReferenceHash string `json:"source_reference_hash"`
	SourceFamily        string `json:"source_family"`
	ContentKind         string `json:"content_kind"`
	LogicalBytes        int64  `json:"logical_bytes"`
	ContentSHA256       string `json:"content_sha256"`
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
	PartIndex     int    `json:"part_index"`
	ByteOffset    int64  `json:"byte_offset"`
	ByteLength    int    `json:"byte_length"`
	ContentSHA256 string `json:"content_sha256"`
	ObjectPath    string `json:"object_path,omitempty"`
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

func IsUUID(value string) bool {
	return isUUID(value)
}

type ManifestPart struct {
	PartIndex     int    `json:"part_index"`
	ByteOffset    int64  `json:"byte_offset"`
	ByteLength    int    `json:"byte_length"`
	ContentSHA256 string `json:"content_sha256"`
}

type ManifestFile struct {
	FileDescriptor
	InclusionState string         `json:"inclusion_state"`
	Parts          []ManifestPart `json:"parts"`
}

type ManifestCreateRequest struct {
	CreateRequest
	PageContentSHA256 string         `json:"page_content_sha256"`
	Files             []ManifestFile `json:"files"`
}

func (request ManifestCreateRequest) Validate() error {
	if err := request.CreateRequest.Validate(); err != nil {
		return err
	}
	if !isSHA256(request.PageContentSHA256) {
		return errors.New("page_content_sha256 must be a lowercase SHA-256 value")
	}
	if len(request.Files) > MaxManifestPageFileCount || len(request.Files) > request.TotalFileCount {
		return errors.New("first manifest page exceeds its file bounds")
	}
	var totalBytes int64
	for index, file := range request.Files {
		if err := validateManifestFile(file); err != nil {
			return fmt.Errorf("files[%d]: %w", index, err)
		}
		totalBytes += file.LogicalBytes
	}
	if totalBytes > request.TotalLogicalBytes || (len(request.Files) == request.TotalFileCount && totalBytes != request.TotalLogicalBytes) {
		return errors.New("first manifest page bytes do not match import totals")
	}
	return nil
}

type ManifestPageRequest struct {
	PageIndex         int            `json:"page_index"`
	PageContentSHA256 string         `json:"page_content_sha256"`
	Files             []ManifestFile `json:"files"`
}

func (request ManifestPageRequest) Validate() error {
	if request.PageIndex < 1 {
		return errors.New("page_index must be at least 1")
	}
	if !isSHA256(request.PageContentSHA256) {
		return errors.New("page_content_sha256 must be a lowercase SHA-256 value")
	}
	if len(request.Files) == 0 || len(request.Files) > MaxManifestPageFileCount {
		return fmt.Errorf("files must contain between 1 and %d entries", MaxManifestPageFileCount)
	}
	for index, file := range request.Files {
		if err := validateManifestFile(file); err != nil {
			return fmt.Errorf("files[%d]: %w", index, err)
		}
	}
	return nil
}

func validateManifestFile(file ManifestFile) error {
	if err := file.FileDescriptor.Validate(); err != nil {
		return err
	}
	if file.InclusionState != "planned" && file.InclusionState != "skipped_duplicate" && file.InclusionState != "excluded" {
		return errors.New("invalid inclusion_state")
	}
	if file.InclusionState != "planned" && len(file.Parts) != 0 {
		return errors.New("excluded or duplicate files cannot have upload parts")
	}
	var expectedOffset int64
	for partIndex, part := range file.Parts {
		if part.PartIndex != partIndex || part.ByteOffset != expectedOffset {
			return errors.New("parts must be contiguous and ordered")
		}
		if part.ByteLength < 1 || part.ByteLength > MaxLogicalPartBytes {
			return fmt.Errorf("parts[%d]: invalid byte_length", partIndex)
		}
		if !isSHA256(part.ContentSHA256) {
			return fmt.Errorf("parts[%d]: invalid content_sha256", partIndex)
		}
		expectedOffset += int64(part.ByteLength)
	}
	if file.InclusionState == "planned" && expectedOffset != file.LogicalBytes {
		return errors.New("part lengths must match logical_bytes")
	}
	return nil
}

type PartPlan struct {
	ID            string `json:"id"`
	PartIndex     int    `json:"part_index"`
	ByteOffset    int64  `json:"byte_offset"`
	ByteLength    int    `json:"byte_length"`
	ContentSHA256 string `json:"content_sha256"`
	ObjectPath    string `json:"object_path"`
	State         string `json:"state"`
}

type FilePlan struct {
	ID                  string     `json:"id"`
	ClientFileID        string     `json:"client_file_id"`
	SourceReferenceHash string     `json:"source_reference_hash"`
	SourceFamily        string     `json:"source_family"`
	ContentKind         string     `json:"content_kind"`
	InclusionState      string     `json:"inclusion_state"`
	LogicalBytes        int64      `json:"logical_bytes"`
	ContentSHA256       string     `json:"content_sha256"`
	Parts               []PartPlan `json:"parts"`
}

type JobSnapshot struct {
	ID      string `json:"id"`
	State   string `json:"state"`
	JobType string `json:"job_type"`
}

type Snapshot struct {
	ID                string       `json:"id"`
	State             ImportState  `json:"state"`
	ManifestVersion   int          `json:"manifest_version"`
	SourceKind        SourceKind   `json:"source_kind"`
	TimezoneCandidate string       `json:"timezone_candidate,omitempty"`
	TotalFileCount    int          `json:"total_file_count"`
	TotalLogicalBytes int64        `json:"total_logical_bytes"`
	CleanupAfter      string       `json:"cleanup_after"`
	Files             []FilePlan   `json:"files"`
	Job               *JobSnapshot `json:"job,omitempty"`
}
