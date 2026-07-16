/// <reference lib="webworker" />

import { createSHA256 } from "hash-wasm";

import { markDuplicateFiles } from "./deduplicate";
import { uuidFromSHA256 } from "./identifiers";
import { classifySourcePath, MAX_DIRECTORY_ENTRIES, normalizeRelativePath } from "./scan-policy";
import type { DirectoryScanInput, DirectoryScanResult, ScanProgress, ScannedFile, ScanWarning } from "./scanner.types";
import { isScanCancelledError, scanZipArchive, ScanCancelledError } from "./zip-scan";
import { StreamingHashes } from "./stream-hashes";

type ScanRequest = { id: string; type: "scan-directory"; files: DirectoryScanInput[] };
type ScanZipRequest = { id: string; type: "scan-zip"; file: File };
type CancelRequest = { id: string; type: "cancel" };
type WorkerRequest = ScanRequest | ScanZipRequest | CancelRequest;

type WorkerResponse =
  | { id: string; type: "progress"; progress: ScanProgress }
  | { id: string; type: "completed"; result: DirectoryScanResult }
  | { id: string; type: "cancelled" }
  | { id: string; type: "failed"; code: "scan_failed" };

const worker = self as DedicatedWorkerGlobalScope;
const cancelledRequests = new Set<string>();

worker.onmessage = (event: MessageEvent<WorkerRequest>) => {
  if (event.data.type === "cancel") {
    cancelledRequests.add(event.data.id);
    return;
  }
  if (event.data.type === "scan-directory") void scanDirectory(event.data);
  if (event.data.type === "scan-zip") void scanZip(event.data);
};

async function scanDirectory(request: ScanRequest): Promise<void> {
  try {
    if (request.files.length > MAX_DIRECTORY_ENTRIES) {
      worker.postMessage({
        id: request.id,
        type: "completed",
        result: { files: [], warnings: [{ code: "entry_limit_exceeded" }] },
      } satisfies WorkerResponse);
      return;
    }

    const files: ScannedFile[] = [];
    const warnings: ScanWarning[] = [];
    for (const [index, entry] of request.files.entries()) {
      if (cancelledRequests.delete(request.id)) {
        worker.postMessage({ id: request.id, type: "cancelled" } satisfies WorkerResponse);
        return;
      }

      const relativePath = normalizeRelativePath(entry.relativePath);
      if (!relativePath) {
        warnings.push({ code: "unsafe_relative_path" });
        worker.postMessage({ id: request.id, type: "progress", progress: { completedFiles: index + 1, totalFiles: request.files.length } } satisfies WorkerResponse);
        continue;
      }

      const classification = classifySourcePath(relativePath);
      if (!classification.included) {
        files.push({
          clientFileId: crypto.randomUUID(),
          contentKind: classification.contentKind,
          contentSha256: null,
          duplicateOfClientFileId: null,
          inclusionState: "excluded",
          logicalBytes: entry.file.size,
          parts: [],
          sourceFamily: classification.sourceFamily,
          sourceReferenceHash: null,
        });
      } else {
        const hashes = await hashStream(entry.file.stream(), request.id);
        const sourceReferenceHash = await sha256Text(relativePath);
        files.push({
          clientFileId: uuidFromSHA256(sourceReferenceHash),
          contentKind: classification.contentKind,
          contentSha256: hashes.contentSha256,
          duplicateOfClientFileId: null,
          inclusionState: "planned",
          logicalBytes: entry.file.size,
          parts: hashes.parts,
          sourceFamily: classification.sourceFamily,
          sourceReferenceHash,
        });
      }
      worker.postMessage({ id: request.id, type: "progress", progress: { completedFiles: index + 1, totalFiles: request.files.length } } satisfies WorkerResponse);
    }
    worker.postMessage({ id: request.id, type: "completed", result: { files: markDuplicateFiles(files), warnings } } satisfies WorkerResponse);
  } catch (error) {
    if (isScanCancelledError(error) || cancelledRequests.delete(request.id)) {
      worker.postMessage({ id: request.id, type: "cancelled" } satisfies WorkerResponse);
      return;
    }
    worker.postMessage({ id: request.id, type: "failed", code: "scan_failed" } satisfies WorkerResponse);
  }
}

async function scanZip(request: ScanZipRequest): Promise<void> {
  try {
    const result = await scanZipArchive(request.file, () => cancelledRequests.has(request.id));
    if (cancelledRequests.delete(request.id)) {
      worker.postMessage({ id: request.id, type: "cancelled" } satisfies WorkerResponse);
      return;
    }
    worker.postMessage({ id: request.id, type: "completed", result: { ...result, files: markDuplicateFiles(result.files) } } satisfies WorkerResponse);
  } catch (error) {
    if (isScanCancelledError(error) || cancelledRequests.delete(request.id)) {
      worker.postMessage({ id: request.id, type: "cancelled" } satisfies WorkerResponse);
      return;
    }
    worker.postMessage({ id: request.id, type: "failed", code: "scan_failed" } satisfies WorkerResponse);
  }
}

async function hashStream(stream: ReadableStream<Uint8Array>, requestID: string) {
  const hashes = await StreamingHashes.create();
  const reader = stream.getReader();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) return hashes.digest();
      if (cancelledRequests.has(requestID)) throw new ScanCancelledError();
      hashes.update(value);
    }
  } finally {
    reader.releaseLock();
  }
}

async function sha256Text(value: string): Promise<string> {
  const hasher = await createSHA256();
  hasher.update(value);
  return hasher.digest("hex");
}
