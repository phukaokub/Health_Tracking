import { isSupported, Upload } from "tus-js-client";

import { getBrowserClient } from "@/lib/supabase/client";

import type { ImportSnapshot } from "./import-api";
import { streamVerifiedZIPParts } from "./zip-part-source";

export const TUS_TRANSPORT_CHUNK_BYTES = 6 * 1024 * 1024;

export type UploadProgress = {
  bytesUploaded: number;
  bytesTotal: number;
  completedParts: number;
  totalParts: number;
};

export class UploadCancelledError extends Error {
  constructor() {
    super("upload_cancelled");
  }
}

export class DirectImportUploader {
  private current: Upload | null = null;
  private activeReject: ((reason: Error) => void) | null = null;
  private cancelled = false;
  private paused = false;
  private resumeWaiters: Array<() => void> = [];

  async upload(snapshot: ImportSnapshot, sourceFiles: Map<string, File>, onProgress: (progress: UploadProgress) => void): Promise<void> {
    if (!isSupported) throw new Error("tus_not_supported");
    this.cancelled = false;
    this.paused = false;
    const files = snapshot.files.filter((file) => file.inclusion_state === "planned");
    const parts = files.flatMap((file) => file.parts.map((part) => ({ file, part })));
    const bytesTotal = parts.reduce((total, item) => total + item.part.byte_length, 0);
    let completedBytes = 0;
    let completedParts = 0;
    onProgress({ bytesUploaded: 0, bytesTotal, completedParts: 0, totalParts: parts.length });

    for (const item of parts) {
      this.throwIfCancelled();
      await this.waitUntilResumed();
      const source = sourceFiles.get(item.file.client_file_id);
      if (!source || source.size !== item.file.logical_bytes) throw new Error("source_file_changed");
      const blob = source.slice(item.part.byte_offset, item.part.byte_offset + item.part.byte_length, "application/octet-stream");
      if (blob.size !== item.part.byte_length || await sha256Blob(blob) !== item.part.content_sha256) {
        throw new Error("source_file_changed");
      }
      await this.uploadPart(blob, item.part.object_path, item.part.content_sha256, (partBytes) => {
        onProgress({
          bytesUploaded: completedBytes + partBytes,
          bytesTotal,
          completedParts,
          totalParts: parts.length,
        });
      });
      completedBytes += item.part.byte_length;
      completedParts += 1;
      onProgress({ bytesUploaded: completedBytes, bytesTotal, completedParts, totalParts: parts.length });
    }
  }

  async uploadZIP(snapshot: ImportSnapshot, archive: Blob, onProgress: (progress: UploadProgress) => void): Promise<void> {
    if (!isSupported) throw new Error("tus_not_supported");
    this.cancelled = false;
    this.paused = false;
    const files = snapshot.files.filter((file) => file.inclusion_state === "planned");
    const totalParts = files.reduce((total, file) => total + file.parts.length, 0);
    const bytesTotal = files.reduce((total, file) => total + file.parts.reduce((fileTotal, part) => fileTotal + part.byte_length, 0), 0);
    let completedBytes = 0;
    let completedParts = 0;
    onProgress({ bytesUploaded: 0, bytesTotal, completedParts: 0, totalParts });

    await streamVerifiedZIPParts(archive, snapshot.files, async (_file, part, blob) => {
      this.throwIfCancelled();
      await this.waitUntilResumed();
      if (blob.size !== part.byte_length || await sha256Blob(blob) !== part.content_sha256) {
        throw new Error("source_archive_changed");
      }
      await this.uploadPart(blob, part.object_path, part.content_sha256, (partBytes) => {
        onProgress({ bytesUploaded: completedBytes + partBytes, bytesTotal, completedParts, totalParts });
      });
      completedBytes += part.byte_length;
      completedParts += 1;
      onProgress({ bytesUploaded: completedBytes, bytesTotal, completedParts, totalParts });
    });
    if (completedParts !== totalParts || completedBytes !== bytesTotal) throw new Error("source_archive_changed");
  }

  async pause(): Promise<void> {
    if (this.cancelled || this.paused) return;
    this.paused = true;
    await this.current?.abort(false);
  }

  resume(): void {
    if (this.cancelled || !this.paused) return;
    this.paused = false;
    const waiters = this.resumeWaiters.splice(0);
    waiters.forEach((resolve) => resolve());
    this.current?.start();
  }

  async cancel(): Promise<void> {
    if (this.cancelled) return;
    this.cancelled = true;
    this.paused = false;
    const waiters = this.resumeWaiters.splice(0);
    waiters.forEach((resolve) => resolve());
    const reject = this.activeReject;
    this.activeReject = null;
    await this.current?.abort(false).catch(() => undefined);
    reject?.(new UploadCancelledError());
  }

  private async uploadPart(blob: Blob, objectPath: string, contentSha256: string, onProgress: (bytes: number) => void): Promise<void> {
    const accessToken = await getAccessToken();
    const supabaseURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
    if (!supabaseURL) throw new Error("supabase_not_configured");
    const endpoint = deriveTUSEndpoint(supabaseURL);
    await new Promise<void>((resolve, reject) => {
      const upload = new Upload(blob, {
        endpoint,
        retryDelays: [0, 3_000, 5_000, 10_000, 20_000],
        headers: { authorization: `Bearer ${accessToken}` },
        uploadDataDuringCreation: true,
        removeFingerprintOnSuccess: true,
        chunkSize: TUS_TRANSPORT_CHUNK_BYTES,
        fingerprint: () => Promise.resolve(`health-import:${objectPath}:${contentSha256}`),
        metadata: {
          bucketName: "health-imports",
          objectName: objectPath,
          contentType: "application/octet-stream",
          cacheControl: "3600",
          metadata: JSON.stringify({ contentSha256 }),
        },
        onError: () => {
          if (!this.cancelled) reject(new Error("upload_failed"));
        },
        onProgress,
        onSuccess: () => resolve(),
      });
      this.current = upload;
      this.activeReject = reject;
      void upload.findPreviousUploads().then(async (previousUploads) => {
        if (previousUploads.length) upload.resumeFromPreviousUpload(previousUploads[0]!);
        await this.waitUntilResumed();
        this.throwIfCancelled();
        upload.start();
      }).catch(() => reject(new Error("upload_resume_failed")));
    }).finally(() => {
      this.current = null;
      this.activeReject = null;
    });
  }

  private throwIfCancelled(): void {
    if (this.cancelled) throw new UploadCancelledError();
  }

  private waitUntilResumed(): Promise<void> {
    if (!this.paused) return Promise.resolve();
    return new Promise((resolve) => this.resumeWaiters.push(resolve));
  }
}

export function deriveTUSEndpoint(supabaseURL: string): string {
  const url = new URL(supabaseURL);
  if (url.protocol === "https:" && url.hostname.endsWith(".supabase.co")) {
    const projectRef = url.hostname.slice(0, -".supabase.co".length);
    if (/^[a-z0-9-]+$/.test(projectRef)) url.hostname = `${projectRef}.storage.supabase.co`;
  }
  url.pathname = "/storage/v1/upload/resumable";
  url.search = "";
  url.hash = "";
  return url.toString();
}

async function getAccessToken(): Promise<string> {
  const { data, error } = await getBrowserClient().auth.getSession();
  if (error || !data.session?.access_token) throw new Error("authentication_required");
  return data.session.access_token;
}

async function sha256Blob(blob: Blob): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", await blob.arrayBuffer());
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
