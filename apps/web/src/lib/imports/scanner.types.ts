export type DirectoryScanInput = {
  file: File;
  relativePath: string;
};

export type ScanProgress = {
  completedFiles: number;
  totalFiles: number;
};

export type ScannedFile = {
  clientFileId: string;
  contentKind: string;
  contentSha256: string | null;
  duplicateOfClientFileId: string | null;
  inclusionState: "planned" | "skipped_duplicate" | "excluded";
  logicalBytes: number;
  parts: ScannedPart[];
  sourceFamily: "huawei-json" | "legacy-xls" | "excluded";
  sourceReferenceHash: string | null;
};

export type ScannedPart = {
  byteLength: number;
  byteOffset: number;
  contentSha256: string;
  partIndex: number;
};

export type ScanWarning = {
  code: "entry_limit_exceeded" | "unsafe_relative_path" | "unsafe_zip_entry" | "zip_entry_size_missing" | "zip_entry_overlap";
};

export type DirectoryScanResult = {
  files: ScannedFile[];
  warnings: ScanWarning[];
};
