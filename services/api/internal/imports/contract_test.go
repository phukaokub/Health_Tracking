package imports

import (
	"strings"
	"testing"
)

const (
	testUserID   = "00000000-0000-4000-8000-000000000001"
	testImportID = "10000000-0000-4000-8000-000000000001"
	testFileID   = "20000000-0000-4000-8000-000000000001"
	testHash     = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
)

func TestCreateRequestValidate(t *testing.T) {
	valid := CreateRequest{
		ManifestVersion:      ManifestVersion,
		SourceKind:           SourceKindDirectory,
		ClientIdempotencyKey: "30000000-0000-4000-8000-000000000001",
		TimezoneCandidate:    "Asia/Bangkok",
		TotalFileCount:       2,
		TotalLogicalBytes:    1024,
	}
	if err := valid.Validate(); err != nil {
		t.Fatalf("valid request rejected: %v", err)
	}

	invalid := valid
	invalid.SourceKind = "folder"
	if err := invalid.Validate(); err == nil {
		t.Fatal("invalid source kind was accepted")
	}

	invalid = valid
	invalid.TotalFileCount = MaxManifestPageFileCount + 1
	if err := invalid.Validate(); err == nil {
		t.Fatal("oversized manifest page was accepted")
	}
}

func TestImportStateTransitions(t *testing.T) {
	if !ImportStateDraft.CanTransitionTo(ImportStateUploading) {
		t.Fatal("draft should transition to uploading")
	}
	if !ImportStateProcessing.CanTransitionTo(ImportStateCompletedWithWarnings) {
		t.Fatal("processing should transition to completed_with_warnings")
	}
	if ImportStateDraft.CanTransitionTo(ImportStateQueued) {
		t.Fatal("draft must not skip directly to queued")
	}
	if ImportStateDeleted.CanTransitionTo(ImportStateUploading) {
		t.Fatal("deleted import must remain terminal")
	}
}

func TestFileDescriptorRejectsRawOrInvalidMetadata(t *testing.T) {
	file := FileDescriptor{
		ClientFileID:        testFileID,
		SourceReferenceHash: testHash,
		SourceFamily:        "huawei-health-json",
		ContentKind:         "application/json",
		LogicalBytes:        128,
		ContentSHA256:       testHash,
	}
	if err := file.Validate(); err != nil {
		t.Fatalf("valid file descriptor rejected: %v", err)
	}

	file.SourceReferenceHash = "export/health.json"
	if err := file.Validate(); err == nil {
		t.Fatal("raw source reference was accepted")
	}
}

func TestPartDescriptorEnforcesImmutablePathAndSize(t *testing.T) {
	part := PartDescriptor{
		PartIndex:     0,
		ByteOffset:    0,
		ByteLength:    MaxLogicalPartBytes,
		ContentSHA256: testHash,
		ObjectPath:    ObjectPath(testUserID, testImportID, testFileID, 0),
	}
	if err := part.Validate(testUserID, testImportID, testFileID); err != nil {
		t.Fatalf("valid part rejected: %v", err)
	}

	part.ByteLength++
	if err := part.Validate(testUserID, testImportID, testFileID); err == nil {
		t.Fatal("part larger than 20 MiB was accepted")
	}

	part.ByteLength = 1
	part.ObjectPath = "imports/other-user/part-0"
	if err := part.Validate(testUserID, testImportID, testFileID); err == nil || !strings.Contains(err.Error(), "object_path") {
		t.Fatalf("tampered object path should be rejected, got %v", err)
	}
}
