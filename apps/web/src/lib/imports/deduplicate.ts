import type { ScannedFile } from "./scanner.types";

// Duplicate detection is scoped to one client manifest. It uses exact content
// hash plus byte length and returns opaque client IDs only; source paths remain
// inside the scanner Worker.
export function markDuplicateFiles(files: ScannedFile[]): ScannedFile[] {
  const firstByContent = new Map<string, string>();
  return files.map((file) => {
    if (file.inclusionState !== "planned" || !file.contentSha256) return file;

    const key = `${file.logicalBytes}:${file.contentSha256}`;
    const duplicateOfClientFileId = firstByContent.get(key);
    if (duplicateOfClientFileId) {
      return { ...file, duplicateOfClientFileId, inclusionState: "skipped_duplicate" };
    }
    firstByContent.set(key, file.clientFileId);
    return file;
  });
}
