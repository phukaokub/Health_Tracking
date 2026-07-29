"use client";

import { useEffect, useState } from "react";

import { getImport, ImportAPIError, type ImportSnapshot } from "@/lib/imports/import-api";
import {
  isProcessingState,
  processingProgress,
  processingRecordCount,
  processingWarningCodes,
  warningLabel,
} from "@/lib/imports/processing-status";

const POLL_INTERVAL_MS = 3_000;

type ProcessingStatusProps = {
  snapshot: ImportSnapshot;
  onSnapshot: (snapshot: ImportSnapshot) => void;
};

export function ProcessingStatus({ snapshot, onSnapshot }: ProcessingStatusProps) {
  const [pollError, setPollError] = useState<string | null>(null);
  const warningCodes = processingWarningCodes(snapshot);
  const progress = processingProgress(snapshot);
  const recordCount = processingRecordCount(snapshot);

  useEffect(() => {
    if (!isProcessingState(snapshot.state)) return;
    let active = true;
    let timer: ReturnType<typeof setTimeout> | undefined;

    async function poll() {
      try {
        const next = await getImport(snapshot.id);
        if (!active) return;
        setPollError(null);
        onSnapshot(next);
        if (isProcessingState(next.state)) timer = setTimeout(() => void poll(), POLL_INTERVAL_MS);
      } catch (error) {
        if (!active) return;
        setPollError(error instanceof ImportAPIError && error.status === 401
          ? "Your session expired. Sign in again to view processing progress."
          : "Progress is temporarily unavailable; we will retry shortly.");
        timer = setTimeout(() => void poll(), POLL_INTERVAL_MS);
      }
    }

    void poll();
    return () => {
      active = false;
      if (timer) clearTimeout(timer);
    };
  }, [onSnapshot, snapshot.id, snapshot.state]);

  const stateCopy: Record<ImportSnapshot["state"], string> = {
    uploading: "Upload in progress",
    uploaded: "Upload verified",
    queued: "Queued for processing",
    processing: "Processing your export",
    completed: "Import complete",
    completed_with_warnings: "Import complete with warnings",
    failed: "Import could not be completed",
    deleting: "Deleting import data",
    deleted: "Import data deleted",
    cancelling: "Cancelling import",
    cancelled: "Import cancelled",
  };

  return (
    <section className="mt-6 rounded-2xl border border-cyan-200/20 bg-cyan-300/10 p-4" aria-live="polite" aria-label="Import processing status">
      <div className="flex items-center justify-between gap-4 text-sm">
        <span className="font-medium text-cyan-50">{stateCopy[snapshot.state]}</span>
        {progress !== null && snapshot.state === "processing" ? <span className="text-cyan-100">{progress}%</span> : null}
      </div>
      {progress !== null && snapshot.state === "processing" ? (
        <div className="mt-3 h-2 overflow-hidden rounded-full bg-slate-800" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={progress}>
          <div className="h-full bg-cyan-300 transition-[width]" style={{ width: `${progress}%` }} />
        </div>
      ) : null}
      {snapshot.state === "processing" ? (
        <p className="mt-2 text-xs text-slate-300">
          {snapshot.job?.processed_file_count ?? 0} of {snapshot.total_file_count} files reviewed - {recordCount} normalized records
        </p>
      ) : null}
      {snapshot.state === "completed" || snapshot.state === "completed_with_warnings" ? (
        <p className="mt-2 text-xs text-slate-300">{recordCount} normalized records are ready for your private reports.</p>
      ) : null}
      {pollError ? <p className="mt-3 text-xs text-amber-100">{pollError}</p> : null}
      {warningCodes.length ? (
        <ul className="mt-3 space-y-1 text-xs text-amber-100">
          {warningCodes.map((code) => <li key={code}>{warningLabel(code)}</li>)}
        </ul>
      ) : null}
      <p className="mt-3 text-xs text-slate-400">Only progress counts and safe warning summaries are shown; source names, paths, and health values are never displayed.</p>
    </section>
  );
}
