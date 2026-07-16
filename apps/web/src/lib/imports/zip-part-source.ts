import { createSHA256 } from "hash-wasm";
import { Unzip, UnzipInflate } from "fflate";

import type { ImportFilePlan, ImportPartPlan } from "./import-api";
import { uuidFromSHA256 } from "./identifiers";
import {
  classifySourcePath,
  isSafeZipEntry,
  MAX_DIRECTORY_ENTRIES,
  MAX_UNCOMPRESSED_BYTES,
  normalizeRelativePath,
} from "./scan-policy";

const ZIP_INPUT_CHUNK_BYTES = 4 * 1024;

export async function streamVerifiedZIPParts(
  archive: Blob,
  files: ImportFilePlan[],
  onPart: (file: ImportFilePlan, part: ImportPartPlan, blob: Blob) => Promise<void>,
): Promise<void> {
  const referenceHasher = await createSHA256();
  const expected = new Map(files.map((file) => [file.client_file_id, file]));
  const seenPlanned = new Set<string>();
  let completedParts = 0;
  let entryCount = 0;
  let totalUncompressedBytes = 0;
  let activeEntry = false;
  let deferredError: Error | null = null;
  let pending = Promise.resolve();

  const unzip = new Unzip((entry) => {
    entryCount += 1;
    if (entryCount > MAX_DIRECTORY_ENTRIES || activeEntry) {
      deferredError = new Error("source_archive_changed");
      return;
    }
    const relativePath = normalizeRelativePath(entry.name);
    if (!relativePath || entry.size === undefined || entry.originalSize === undefined) {
      deferredError = new Error("source_archive_changed");
      return;
    }
    if (!isSafeZipEntry(relativePath, entry.originalSize, entry.size)
      || totalUncompressedBytes + entry.originalSize > MAX_UNCOMPRESSED_BYTES) {
      deferredError = new Error("source_archive_changed");
      return;
    }
    totalUncompressedBytes += entry.originalSize;

    const classification = classifySourcePath(relativePath);
    if (!classification.included) return;
    referenceHasher.init().update(relativePath);
    const clientFileID = uuidFromSHA256(referenceHasher.digest("hex"));
    const file = expected.get(clientFileID);
    if (!file) {
      deferredError = new Error("source_archive_changed");
      return;
    }
    if (file.inclusion_state === "skipped_duplicate") return;
    if (file.inclusion_state !== "planned"
      || file.logical_bytes !== entry.originalSize
      || file.source_family !== classification.sourceFamily
      || file.content_kind !== classification.contentKind
      || seenPlanned.has(clientFileID)) {
      deferredError = new Error("source_archive_changed");
      return;
    }

    activeEntry = true;
    seenPlanned.add(clientFileID);
    let partIndex = 0;
    let partBytes = 0;
    let chunks: ArrayBuffer[] = [];
    let receivedBytes = 0;
    entry.ondata = (error, chunk, final) => {
      if (error) {
        deferredError = new Error("source_archive_changed");
        activeEntry = false;
        return;
      }
      if (chunk) {
        receivedBytes += chunk.byteLength;
        if (receivedBytes > file.logical_bytes) {
          deferredError = new Error("source_archive_changed");
          entry.terminate();
          activeEntry = false;
          return;
        }
        let offset = 0;
        while (offset < chunk.byteLength) {
          const part = file.parts[partIndex];
          if (!part) {
            deferredError = new Error("source_archive_changed");
            entry.terminate();
            activeEntry = false;
            return;
          }
          const length = Math.min(part.byte_length - partBytes, chunk.byteLength - offset);
          const copy = new Uint8Array(length);
          copy.set(chunk.subarray(offset, offset + length));
          chunks.push(copy.buffer);
          partBytes += length;
          offset += length;
          if (partBytes === part.byte_length) {
            const blob = new Blob(chunks, { type: "application/octet-stream" });
            pending = pending.then(() => onPart(file, part, blob));
            completedParts += 1;
            partIndex += 1;
            partBytes = 0;
            chunks = [];
          }
        }
      }
      if (final) {
        if (receivedBytes !== file.logical_bytes || partBytes !== 0 || partIndex !== file.parts.length) {
          deferredError = new Error("source_archive_changed");
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
      const { done, value } = await reader.read();
      if (done) break;
      for (let offset = 0; offset < value.byteLength; offset += ZIP_INPUT_CHUNK_BYTES) {
        unzip.push(value.subarray(offset, offset + ZIP_INPUT_CHUNK_BYTES), false);
        await pending;
        if (deferredError) throw deferredError;
      }
    }
    unzip.push(new Uint8Array(), true);
    await pending;
    if (deferredError) throw deferredError;
    const planned = files.filter((file) => file.inclusion_state === "planned");
    const expectedParts = planned.reduce((total, file) => total + file.parts.length, 0);
    if (activeEntry || seenPlanned.size !== planned.length || completedParts !== expectedParts) {
      throw new Error("source_archive_changed");
    }
  } finally {
    reader.releaseLock();
  }
}
