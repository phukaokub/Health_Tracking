"use client";

import { useEffect, useRef, useState } from "react";

import { cleanupExpiredImports, createImport, completeImport, deleteImport, ImportAPIError, type ImportSnapshot } from "@/lib/imports/import-api";
import { DirectoryScanner } from "@/lib/imports/directory-scanner";
import { sha256Text, uuidFromSHA256 } from "@/lib/imports/identifiers";
import { normalizeRelativePath } from "@/lib/imports/scan-policy";
import type { DirectoryScanInput, DirectoryScanResult } from "@/lib/imports/scanner.types";
import { DirectImportUploader, UploadCancelledError, type UploadProgress } from "@/lib/imports/tus-uploader";

type UploadStage = "idle" | "creating" | "uploading" | "paused" | "finalizing" | "queued" | "cancelling" | "cancelled" | "error";

export function ImportScanner() {
  const uploadEnabled = process.env.NEXT_PUBLIC_IMPORT_UPLOAD_ENABLED === "true";
  const inputRef = useRef<HTMLInputElement>(null);
  const zipInputRef = useRef<HTMLInputElement>(null);
  const scannerRef = useRef<DirectoryScanner | null>(null);
  const uploaderRef = useRef<DirectImportUploader | null>(null);
  const directoryFilesRef = useRef(new Map<string, File>());
  const zipFileRef = useRef<File | null>(null);
  const cancellingUploadRef = useRef(false);
  const [progress, setProgress] = useState<{ completedFiles: number; totalFiles: number } | null>(null);
  const [result, setResult] = useState<DirectoryScanResult | null>(null);
  const [sourceKind, setSourceKind] = useState<"directory" | "zip" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cancelled, setCancelled] = useState(false);
  const [isCancelling, setIsCancelling] = useState(false);
  const [uploadStage, setUploadStage] = useState<UploadStage>("idle");
  const [uploadProgress, setUploadProgress] = useState<UploadProgress | null>(null);
  const [snapshot, setSnapshot] = useState<ImportSnapshot | null>(null);
  const [cleanupNotice, setCleanupNotice] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    scannerRef.current = new DirectoryScanner();
    void cleanupExpiredImports().then((cleanup) => {
      if (active && cleanup.deleted_count > 0) {
        setCleanupNotice(`${cleanup.deleted_count} expired import ${cleanup.deleted_count === 1 ? "was" : "were"} removed.`);
      }
    }).catch((cleanupError: unknown) => {
      if (active && cleanupError instanceof ImportAPIError && ![401, 503].includes(cleanupError.status)) {
        setCleanupNotice("An expired import still needs cleanup; this will retry the next time you return.");
      }
    });
    return () => {
      active = false;
      scannerRef.current?.dispose();
      void uploaderRef.current?.pause();
    };
  }, []);

  function chooseDirectory() {
    inputRef.current?.setAttribute("webkitdirectory", "");
    inputRef.current?.setAttribute("directory", "");
    inputRef.current?.click();
  }

  function chooseZip() {
    zipInputRef.current?.click();
  }

  async function scanSelection(event: React.ChangeEvent<HTMLInputElement>) {
    const entries: DirectoryScanInput[] = Array.from(event.target.files ?? []).map((file) => {
      const relativePath = (file as File & { webkitRelativePath?: string }).webkitRelativePath || file.name;
      return { file, relativePath };
    });
    event.target.value = "";
    if (!entries.length || !scannerRef.current) return;

    resetReview("directory");
    zipFileRef.current = null;
    setProgress({ completedFiles: 0, totalFiles: entries.length });
    const sourceFiles = new Map<string, File>();
    for (const entry of entries) {
      const relativePath = normalizeRelativePath(entry.relativePath);
      if (!relativePath) continue;
      sourceFiles.set(uuidFromSHA256(await sha256Text(relativePath)), entry.file);
    }
    directoryFilesRef.current = sourceFiles;
    try {
      setResult(await scannerRef.current.scan(entries, setProgress));
    } catch (scanError) {
      if (scanError instanceof Error && scanError.message === "scan_cancelled") setCancelled(true);
      else setError(scanError instanceof Error ? scanError.message : "scan_failed");
    } finally {
      setProgress(null);
      setIsCancelling(false);
    }
  }

  async function scanZipSelection(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file || !scannerRef.current) return;

    resetReview("zip");
    directoryFilesRef.current.clear();
    zipFileRef.current = file;
    setProgress({ completedFiles: 0, totalFiles: 0 });
    try {
      setResult(await scannerRef.current.scanZip(file));
    } catch (scanError) {
      if (scanError instanceof Error && scanError.message === "scan_cancelled") setCancelled(true);
      else setError(scanError instanceof Error ? scanError.message : "scan_failed");
    } finally {
      setProgress(null);
      setIsCancelling(false);
    }
  }

  function resetReview(kind: "directory" | "zip") {
    setSourceKind(kind);
    setError(null);
    setCancelled(false);
    setIsCancelling(false);
    setResult(null);
    setSnapshot(null);
    setUploadProgress(null);
    setUploadStage("idle");
    cancellingUploadRef.current = false;
  }

  function cancelReview() {
    setIsCancelling(true);
    scannerRef.current?.cancelAll();
  }

  async function startUpload() {
    if (!uploadEnabled || !result || !sourceKind) return;
    cancellingUploadRef.current = false;
    setError(null);
    setUploadStage("creating");
    let created: ImportSnapshot | null = null;
    try {
      created = await createImport(result, sourceKind);
      setSnapshot(created);
      const uploader = new DirectImportUploader();
      uploaderRef.current = uploader;
      setUploadStage("uploading");
      if (sourceKind === "directory") {
        await uploader.upload(created, directoryFilesRef.current, setUploadProgress);
      } else {
        if (!zipFileRef.current) throw new Error("source_archive_changed");
        await uploader.uploadZIP(created, zipFileRef.current, setUploadProgress);
      }
      setUploadStage("finalizing");
      const completed = await completeImport(created.id);
      setSnapshot(completed);
      setUploadStage("queued");
    } catch (uploadError) {
      if (cancellingUploadRef.current || uploadError instanceof UploadCancelledError) return;
      if (uploadError instanceof ImportAPIError && uploadError.importID) {
        await deleteImport(uploadError.importID).catch(() => undefined);
      }
      setError(uploadError instanceof Error ? uploadError.message : "upload_failed");
      setUploadStage("error");
    }
  }

  async function pauseUpload() {
    await uploaderRef.current?.pause();
    setUploadStage("paused");
  }

  function resumeUpload() {
    uploaderRef.current?.resume();
    setUploadStage("uploading");
  }

  async function cancelUpload() {
    if (!snapshot) return;
    cancellingUploadRef.current = true;
    setUploadStage("cancelling");
    await uploaderRef.current?.cancel();
    try {
      const deleted = await deleteImport(snapshot.id);
      setSnapshot(deleted);
      setUploadStage("cancelled");
      setUploadProgress(null);
    } catch {
      setError("cleanup_failed");
      setUploadStage("error");
    }
  }

  const planned = result?.files.filter((file) => file.inclusionState === "planned").length ?? 0;
  const duplicates = result?.files.filter((file) => file.inclusionState === "skipped_duplicate").length ?? 0;
  const excluded = result?.files.filter((file) => file.inclusionState === "excluded").length ?? 0;
  const isBusy = progress !== null || ["creating", "uploading", "paused", "finalizing", "cancelling"].includes(uploadStage);
  const percentage = uploadProgress?.bytesTotal ? Math.round((uploadProgress.bytesUploaded / uploadProgress.bytesTotal) * 100) : 0;

  return (
    <section className="rounded-3xl border border-white/10 bg-white/10 p-6">
      <h1 className="text-3xl font-semibold">Review files before import</h1>
      <p className="mt-3 text-slate-300">
        Review happens on this device. Choose a folder or ZIP file from your health app. When you upload, supported files go directly to private Supabase Storage and never pass through Next.js or the Go API.
      </p>
      {cleanupNotice ? <p className="mt-3 text-sm text-amber-100" aria-live="polite">{cleanupNotice}</p> : null}
      <input ref={inputRef} className="sr-only" type="file" multiple onChange={scanSelection} />
      <input ref={zipInputRef} className="sr-only" type="file" accept=".zip,application/zip" onChange={scanZipSelection} />
      <button disabled={isBusy} className="mt-6 rounded-full bg-white px-5 py-2 text-sm font-semibold text-slate-950 disabled:cursor-not-allowed disabled:opacity-50" type="button" onClick={chooseDirectory}>
        Choose a folder
      </button>
      <button disabled={isBusy} className="ml-3 mt-6 rounded-full border border-white/20 px-5 py-2 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50" type="button" onClick={chooseZip}>
        Choose a ZIP file
      </button>

      {progress ? (
        <div className="mt-4 flex items-center gap-3">
          <p className="text-sm text-slate-300">{progress.totalFiles ? `Reviewing ${progress.completedFiles} of ${progress.totalFiles} files…` : "Reviewing ZIP archive…"}</p>
          <button disabled={isCancelling} className="rounded-full border border-red-200/40 px-3 py-1 text-xs font-medium text-red-100 disabled:opacity-50" type="button" onClick={cancelReview}>{isCancelling ? "Cancelling…" : "Cancel review"}</button>
        </div>
      ) : null}
      {cancelled ? <p className="mt-4 text-sm text-amber-200">Review cancelled. No files were uploaded or retained.</p> : null}
      {error ? <p className="mt-4 text-sm text-red-200">Unable to continue ({friendlyError(error)}).</p> : null}

      {result ? (
        <div className="mt-6 rounded-2xl bg-slate-900/70 p-4 text-sm text-slate-200">
          <p><span className="font-medium text-white">{planned}</span> supported files; <span className="font-medium text-white">{duplicates}</span> exact duplicates skipped; <span className="font-medium text-white">{excluded}</span> excluded.</p>
          {result.warnings.length ? <p className="mt-2 text-amber-200">Some entries were ignored because their path or size policy was unsafe.</p> : null}
          <p className="mt-3 text-slate-400">Names, paths, file contents, and health values are not displayed or sent as metadata.</p>
          {sourceKind && planned > 0 && uploadStage === "idle" && uploadEnabled ? (
            <button className="mt-4 rounded-full bg-emerald-300 px-5 py-2 font-semibold text-slate-950" type="button" onClick={startUpload}>Upload files for import</button>
          ) : null}
          {sourceKind && planned > 0 && !uploadEnabled ? <p className="mt-4 text-cyan-100">Direct upload is disabled until the current Step 3 verification window is explicitly enabled.</p> : null}
        </div>
      ) : null}

      {uploadProgress && !["cancelled", "queued"].includes(uploadStage) ? (
        <div className="mt-6 rounded-2xl border border-cyan-200/20 bg-cyan-300/10 p-4" aria-live="polite">
          <div className="flex items-center justify-between text-sm"><span>{uploadStage === "paused" ? "Upload paused" : uploadStage === "finalizing" ? "Verifying upload" : "Uploading directly to private Storage"}</span><span>{percentage}%</span></div>
          <div className="mt-3 h-2 overflow-hidden rounded-full bg-slate-800"><div className="h-full bg-cyan-300 transition-[width]" style={{ width: `${percentage}%` }} /></div>
          <p className="mt-2 text-xs text-slate-300">{uploadProgress.completedParts} of {uploadProgress.totalParts} immutable parts complete.</p>
          <div className="mt-4 flex gap-2">
            {uploadStage === "uploading" ? <button className="rounded-full border border-white/20 px-4 py-1.5 text-sm" type="button" onClick={pauseUpload}>Pause</button> : null}
            {uploadStage === "paused" ? <button className="rounded-full border border-white/20 px-4 py-1.5 text-sm" type="button" onClick={resumeUpload}>Resume</button> : null}
            {snapshot && ["uploading", "paused", "error"].includes(uploadStage) ? <button className="rounded-full border border-red-200/40 px-4 py-1.5 text-sm text-red-100" type="button" onClick={cancelUpload}>Cancel and delete</button> : null}
          </div>
        </div>
      ) : null}

      {uploadStage === "queued" ? <p className="mt-6 rounded-2xl bg-emerald-300/10 p-4 text-sm text-emerald-100">Upload verified and queued. Parsing begins in Step 4.</p> : null}
      {uploadStage === "cancelled" ? <p className="mt-6 text-sm text-amber-200">Import cancelled and uploaded objects deleted.</p> : null}
      {uploadStage === "error" && snapshot ? <button className="mt-4 rounded-full border border-white/20 px-4 py-2 text-sm" type="button" onClick={startUpload}>Retry or resume upload</button> : null}
    </section>
  );
}

function friendlyError(code: string): string {
  const messages: Record<string, string> = {
    api_not_configured: "the API is not configured",
    authentication_required: "your session expired; sign in again",
    cleanup_failed: "cleanup could not finish; retry cancellation",
    import_rejected: "the metadata plan was rejected",
    no_supported_files: "no supported files were selected",
    source_file_changed: "a selected file changed after review; select the folder again",
    source_archive_changed: "the selected ZIP changed or no longer matches its reviewed manifest; select it again",
    supabase_not_configured: "Supabase is not configured",
    tus_not_supported: "this browser does not support resumable uploads",
    upload_failed: "the upload was interrupted; retry to resume",
    upload_resume_failed: "the saved upload could not be resumed",
  };
  return messages[code] ?? "an unexpected import error occurred";
}
