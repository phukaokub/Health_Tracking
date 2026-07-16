import { getBrowserClient } from "@/lib/supabase/client";

import { sha256Text, uuidFromSHA256 } from "./identifiers";
import type { DirectoryScanResult, ScannedFile } from "./scanner.types";

const MANIFEST_PAGE_FILES = 1_000;
const MANIFEST_PAGE_BYTES = 900 * 1_024;

export type ImportSourceKind = "directory" | "zip";

export type ImportPartPlan = {
  id: string;
  part_index: number;
  byte_offset: number;
  byte_length: number;
  content_sha256: string;
  object_path: string;
  state: string;
};

export type ImportFilePlan = {
  id: string;
  client_file_id: string;
  source_family: string;
  inclusion_state: "planned" | "skipped_duplicate" | "excluded" | "uploaded" | "verified" | "deleted";
  logical_bytes: number;
  content_sha256: string;
  content_kind: string;
  parts: ImportPartPlan[];
};

export type ImportSnapshot = {
  id: string;
  state: "uploading" | "uploaded" | "queued" | "processing" | "completed" | "completed_with_warnings" | "failed" | "deleting" | "deleted";
  total_file_count: number;
  total_logical_bytes: number;
  files: ImportFilePlan[];
  job?: { id: string; state: string; job_type: string } | null;
};

export class ImportAPIError extends Error {
  constructor(
    public readonly code: string,
    public readonly status: number,
    public readonly importID?: string,
  ) {
    super(code);
  }
}

export type ManifestFile = {
  client_file_id: string;
  source_reference_hash: string;
  source_family: string;
  content_kind: string;
  inclusion_state: "planned" | "skipped_duplicate";
  logical_bytes: number;
  content_sha256: string;
  parts: Array<{ part_index: number; byte_offset: number; byte_length: number; content_sha256: string }>;
};

export async function createImport(result: DirectoryScanResult, sourceKind: ImportSourceKind): Promise<ImportSnapshot> {
  const files = result.files.flatMap(toManifestFile);
  if (files.length === 0 || !files.some((file) => file.inclusion_state === "planned")) {
    throw new ImportAPIError("no_supported_files", 400);
  }
  const pages = paginateManifestFiles(files);
  const totalLogicalBytes = files.reduce((total, file) => total + file.logical_bytes, 0);
  const idempotencyHash = await sha256Text(JSON.stringify({ version: 1, sourceKind, files }));
  const clientIdempotencyKey = uuidFromSHA256(idempotencyHash);
  const firstFiles = pages[0]!;
  let snapshot: ImportSnapshot | undefined;
  try {
    snapshot = await apiFetch<ImportSnapshot>("/api/v1/imports", {
      method: "POST",
      body: JSON.stringify({
        manifest_version: 1,
        source_kind: sourceKind,
        client_idempotency_key: clientIdempotencyKey,
        timezone_candidate: Intl.DateTimeFormat().resolvedOptions().timeZone,
        total_file_count: files.length,
        total_logical_bytes: totalLogicalBytes,
        page_content_sha256: await manifestPageHash(firstFiles),
        files: firstFiles,
      }),
    });
    for (let pageIndex = 1; pageIndex < pages.length; pageIndex += 1) {
      const pageFiles = pages[pageIndex]!;
      snapshot = await apiFetch<ImportSnapshot>(`/api/v1/imports/${snapshot.id}/manifest-pages`, {
        method: "POST",
        body: JSON.stringify({
          page_index: pageIndex,
          page_content_sha256: await manifestPageHash(pageFiles),
          files: pageFiles,
        }),
      });
    }
    return snapshot;
  } catch (error) {
    if (error instanceof ImportAPIError && snapshot?.id) {
      throw new ImportAPIError(error.code, error.status, snapshot.id);
    }
    throw error;
  }
}

export function completeImport(importID: string): Promise<ImportSnapshot> {
  return apiFetch(`/api/v1/imports/${importID}/complete`, { method: "POST" });
}

export function deleteImport(importID: string): Promise<ImportSnapshot> {
  return apiFetch(`/api/v1/imports/${importID}`, { method: "DELETE" });
}

export function getImport(importID: string): Promise<ImportSnapshot> {
  return apiFetch(`/api/v1/imports/${importID}`, { method: "GET" });
}

export function cleanupExpiredImports(): Promise<{ deleted_count: number }> {
  return apiFetch("/api/v1/imports/cleanup", { method: "POST" });
}

function toManifestFile(file: ScannedFile): ManifestFile[] {
  if (!file.contentSha256 || !file.sourceReferenceHash || file.inclusionState === "excluded") return [];
  return [{
    client_file_id: file.clientFileId,
    source_reference_hash: file.sourceReferenceHash,
    source_family: file.sourceFamily,
    content_kind: file.contentKind,
    inclusion_state: file.inclusionState,
    logical_bytes: file.logicalBytes,
    content_sha256: file.contentSha256,
    parts: file.inclusionState === "planned" ? file.parts.map((part) => ({
      part_index: part.partIndex,
      byte_offset: part.byteOffset,
      byte_length: part.byteLength,
      content_sha256: part.contentSha256,
    })) : [],
  }];
}

async function manifestPageHash(files: ManifestFile[]): Promise<string> {
  return sha256Text(JSON.stringify(files));
}

async function accessToken(): Promise<string> {
  const { data, error } = await getBrowserClient().auth.getSession();
  if (error || !data.session?.access_token) throw new ImportAPIError("authentication_required", 401);
  return data.session.access_token;
}

async function apiFetch<T>(path: string, init: RequestInit): Promise<T> {
  const baseURL = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (!baseURL) throw new ImportAPIError("api_not_configured", 503);
  const response = await fetch(new URL(path, ensureTrailingSlash(baseURL)), {
    ...init,
    cache: "no-store",
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  });
  const payload = await response.json().catch(() => ({})) as { error?: string };
  if (!response.ok) throw new ImportAPIError(payload.error ?? "api_unavailable", response.status);
  return payload as T;
}

export function paginateManifestFiles(
  files: ManifestFile[],
  byteBudget = MANIFEST_PAGE_BYTES,
): ManifestFile[][] {
  const pages: ManifestFile[][] = [];
  let page: ManifestFile[] = [];
  let pageBytes = 2; // JSON array brackets.

  for (const file of files) {
    const fileBytes = new TextEncoder().encode(JSON.stringify(file)).byteLength;
    const nextBytes = pageBytes + fileBytes + (page.length === 0 ? 0 : 1);
    if (page.length > 0 && (page.length >= MANIFEST_PAGE_FILES || nextBytes > byteBudget)) {
      pages.push(page);
      page = [];
      pageBytes = 2;
    }
    if (fileBytes + 2 > byteBudget) {
      throw new ImportAPIError("manifest_file_metadata_too_large", 413);
    }
    page.push(file);
    pageBytes += fileBytes + (page.length === 1 ? 0 : 1);
  }
  if (page.length > 0) pages.push(page);
  return pages;
}

function ensureTrailingSlash(value: string): string {
  return value.endsWith("/") ? value : `${value}/`;
}
