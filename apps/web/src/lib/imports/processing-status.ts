import type { ImportSnapshot } from "./import-api";

const SAFE_WARNING_LABELS: Record<string, string> = {
  json_truncated: "The export ended before all records could be read.",
  metric_mapping_unknown: "Some metrics were not recognized and were skipped.",
  motion_json_invalid: "Some motion details could not be read safely.",
  route_content_dropped: "Route details were omitted to protect your privacy.",
  source_schema_unsupported: "One source format was not supported.",
  timestamp_invalid: "Some records had unusable timestamps and were skipped.",
  unit_unsupported: "Some measurements used unsupported units and were skipped.",
};

export function processingProgress(snapshot: ImportSnapshot): number | null {
  const processed = snapshot.job?.processed_file_count ?? 0;
  if (snapshot.total_file_count <= 0 || processed < 0) return null;
  return Math.min(100, Math.round((processed / snapshot.total_file_count) * 100));
}

export function processingRecordCount(snapshot: ImportSnapshot): number {
  return snapshot.job?.normalized_record_count ?? snapshot.normalization?.normalized_record_count ?? 0;
}

export function processingWarningCodes(snapshot: ImportSnapshot): string[] {
  return snapshot.job?.warning_codes ?? snapshot.normalization?.warning_codes ?? [];
}

export function warningLabel(code: string): string {
  return SAFE_WARNING_LABELS[code] ?? "Some source fields were skipped during normalization.";
}

export function isProcessingState(state: ImportSnapshot["state"]): boolean {
  return state === "queued" || state === "processing";
}
