import { createSHA256 } from "hash-wasm";
import { Unzip, UnzipInflate } from "fflate";

import { classifySourcePath, isSafeZipEntry, MAX_DIRECTORY_ENTRIES, MAX_UNCOMPRESSED_BYTES, normalizeRelativePath } from "./scan-policy";
import type { DirectoryScanResult, ScannedFile, ScanWarning } from "./scanner.types";

export class ScanCancelledError extends Error {
  constructor() {
    super("scan_cancelled");
  }
}

export function isScanCancelledError(error: unknown): boolean {
  return error instanceof ScanCancelledError;
}

// scanZipArchive streams compressed archive bytes and only retains bounded
// metadata/checksums. It never returns a name or path from the archive.
export async function scanZipArchive(archive: Blob, isCancelled: () => boolean): Promise<DirectoryScanResult> {
  const contentHasher = await createSHA256();
  const referenceHasher = await createSHA256();
  const files: ScannedFile[] = [];
  const warnings: ScanWarning[] = [];
  let entryCount = 0;
  let totalUncompressedBytes = 0;
  let activeEntry = false;
  let deferredError: Error | null = null;

  const unzip = new Unzip((entry) => {
    entryCount += 1;
    if (entryCount > MAX_DIRECTORY_ENTRIES) {
      deferredError = new Error("entry_limit_exceeded");
      return;
    }
    if (activeEntry) {
      warnings.push({ code: "zip_entry_overlap" });
      return;
    }

    const relativePath = normalizeRelativePath(entry.name);
    if (!relativePath || entry.size === undefined || entry.originalSize === undefined) {
      warnings.push({ code: relativePath ? "zip_entry_size_missing" : "unsafe_zip_entry" });
      return;
    }
    if (!isSafeZipEntry(relativePath, entry.originalSize, entry.size) || totalUncompressedBytes + entry.originalSize > MAX_UNCOMPRESSED_BYTES) {
      warnings.push({ code: "unsafe_zip_entry" });
      return;
    }
    totalUncompressedBytes += entry.originalSize;

    const classification = classifySourcePath(relativePath);
    if (!classification.included) {
      files.push({
        clientFileId: crypto.randomUUID(),
        contentKind: classification.contentKind,
        contentSha256: null,
        inclusionState: "excluded",
        logicalBytes: entry.originalSize,
        sourceFamily: classification.sourceFamily,
        sourceReferenceHash: null,
      });
      return;
    }

    activeEntry = true;
    referenceHasher.init().update(relativePath);
    const sourceReferenceHash = referenceHasher.digest("hex");
    contentHasher.init();
    let receivedBytes = 0;
    entry.ondata = (error, chunk, final) => {
      if (error) {
        deferredError = error;
        activeEntry = false;
        return;
      }
      if (isCancelled()) {
        deferredError = new ScanCancelledError();
        entry.terminate();
        activeEntry = false;
        return;
      }
      if (chunk) {
        receivedBytes += chunk.byteLength;
        if (receivedBytes > entry.originalSize!) {
          deferredError = new Error("unsafe_zip_entry");
          entry.terminate();
          activeEntry = false;
          return;
        }
        contentHasher.update(chunk);
      }
      if (final) {
        if (receivedBytes !== entry.originalSize) {
          deferredError = new Error("unsafe_zip_entry");
        } else {
          files.push({
            clientFileId: crypto.randomUUID(),
            contentKind: classification.contentKind,
            contentSha256: contentHasher.digest("hex"),
            inclusionState: "planned",
            logicalBytes: entry.originalSize!,
            sourceFamily: classification.sourceFamily,
            sourceReferenceHash,
          });
        }
        activeEntry = false;
      }
    };
    entry.start();
  });
  unzip.register(UnzipInflate);

  const reader = archive.stream().getReader();
  try {
    while (true) {
      if (isCancelled()) throw new ScanCancelledError();
      const { done, value } = await reader.read();
      if (done) break;
      unzip.push(value, false);
      if (deferredError) throw deferredError;
    }
    unzip.push(new Uint8Array(), true);
    if (deferredError) throw deferredError;
    if (activeEntry) throw new Error("unsafe_zip_entry");
    if (entryCount === 0) throw new Error("unsafe_zip_entry");
    return { files, warnings };
  } finally {
    reader.releaseLock();
  }
}
