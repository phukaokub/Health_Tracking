export const MAX_DIRECTORY_ENTRIES = 5_000;
export const MAX_UNCOMPRESSED_BYTES = 2 * 1024 * 1024 * 1024;
export const MAX_ZIP_EXPANSION_RATIO = 100;

export type SourceFamily = "huawei-json" | "legacy-xls" | "excluded";

export type SourceClassification = {
  contentKind: string;
  included: boolean;
  sourceFamily: SourceFamily;
};

export function normalizeRelativePath(value: string): string | null {
  if (!value || value.length > 1024 || /[\u0000-\u001f\u007f]/.test(value)) return null;
  const normalized = value.replace(/\\/g, "/");
  if (normalized.startsWith("/") || /^[a-zA-Z]:\//.test(normalized)) return null;

  const segments = normalized.split("/");
  if (segments.some((segment) => !segment || segment === "." || segment === "..")) return null;
  return normalized;
}

export function classifySourcePath(path: string): SourceClassification {
  const extension = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
  if (extension === "json") {
    return { sourceFamily: "huawei-json", contentKind: "application/json", included: true };
  }
  if (extension === "xls" || extension === "xlsx") {
    return {
      sourceFamily: "legacy-xls",
      contentKind: extension === "xls" ? "application/vnd.ms-excel" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      included: true,
    };
  }
  return { sourceFamily: "excluded", contentKind: "application/octet-stream", included: false };
}

export function isSafeZipEntry(path: string, uncompressedBytes: number, compressedBytes: number): boolean {
  if (!normalizeRelativePath(path) || uncompressedBytes < 0 || uncompressedBytes > MAX_UNCOMPRESSED_BYTES) return false;
  if (compressedBytes <= 0) return uncompressedBytes === 0;
  return uncompressedBytes / compressedBytes <= MAX_ZIP_EXPANSION_RATIO;
}
