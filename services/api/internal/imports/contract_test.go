package imports

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestNormalizationSnapshotDoesNotContainPayloadFields(t *testing.T) {
	snapshot := Snapshot{Normalization: &NormalizationSnapshot{
		NormalizedRecordCount: 2,
		WarningCodes:          []string{"sensitive_record_excluded"},
	}, Job: &JobSnapshot{
		ProcessedFileCount:    1,
		NormalizedRecordCount: 2,
		WarningCodes:          []string{"route_content_dropped"},
	}}
	encoded, err := json.Marshal(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"payload", "path", "email", "waveform", "latitude", "longitude"} {
		if strings.Contains(string(encoded), forbidden) {
			t.Fatalf("unsafe field %q present in API contract: %s", forbidden, encoded)
		}
	}
}

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
	invalid.TotalFileCount = MaxManifestFileCount + 1
	if err := invalid.Validate(); err == nil {
		t.Fatal("oversized import was accepted")
	}
}

func TestManifestRequestsSeparateImportAndPageLimits(t *testing.T) {
	file := ManifestFile{
		FileDescriptor: FileDescriptor{
			ClientFileID:        testFileID,
			SourceReferenceHash: testHash,
			SourceFamily:        "synthetic-json",
			ContentKind:         "application/json",
			LogicalBytes:        1,
			ContentSHA256:       testHash,
		},
		InclusionState: "planned",
		Parts: []ManifestPart{{
			PartIndex: 0, ByteOffset: 0, ByteLength: 1, ContentSHA256: testHash,
		}},
	}
	create := ManifestCreateRequest{
		CreateRequest: CreateRequest{
			ManifestVersion: ManifestVersion, SourceKind: SourceKindDirectory,
			ClientIdempotencyKey: "30000000-0000-4000-8000-000000000001",
			TotalFileCount:       2, TotalLogicalBytes: 2,
		},
		PageContentSHA256: testHash,
		Files:             []ManifestFile{file},
	}
	if err := create.Validate(); err != nil {
		t.Fatalf("bounded first page of a larger import was rejected: %v", err)
	}
	page := ManifestPageRequest{PageIndex: 1, PageContentSHA256: testHash, Files: []ManifestFile{file}}
	if err := page.Validate(); err != nil {
		t.Fatalf("valid follow-up page was rejected: %v", err)
	}
	page.PageIndex = 0
	if err := page.Validate(); err == nil {
		t.Fatal("page zero was accepted as a follow-up page")
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
