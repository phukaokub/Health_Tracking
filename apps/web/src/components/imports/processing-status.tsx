"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

import { CURRENT_PARSER_VERSION, getImport, ImportAPIError, requeueImport, type ImportSnapshot } from "@/lib/imports/import-api";
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
  const [requeueError, setRequeueError] = useState<string | null>(null);
  const [isRequeueing, setIsRequeueing] = useState(false);
  const warningCodes = processingWarningCodes(snapshot);
  const progress = processingProgress(snapshot);
  const recordCount = processingRecordCount(snapshot);
  const canRequeue = (snapshot.state === "completed" || snapshot.state === "completed_with_warnings" || snapshot.state === "failed")
    && Boolean(snapshot.job?.parser_version)
    && snapshot.job?.parser_version !== CURRENT_PARSER_VERSION;

  async function handleRequeue() {
    setIsRequeueing(true);
    setRequeueError(null);
    try {
      onSnapshot(await requeueImport(snapshot.id));
    } catch (error) {
      setRequeueError(error instanceof ImportAPIError && error.code === "raw_source_unavailable"
        ? "The private source parts have expired; upload the export again to reprocess it."
        : "Reprocessing could not be queued; try again shortly.");
    } finally {
      setIsRequeueing(false);
    }
  }

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
        <p className="mt-2 text-xs text-slate-300">{recordCount > 0 ? `${recordCount} normalized records are ready for your private reports.` : "No normalized records were created yet; review the warnings below or try another export."}</p>
      ) : null}
      {snapshot.normalization?.legacy_backfill ? (
        <div className="mt-3 rounded-xl border border-cyan-100/15 bg-slate-950/30 p-3 text-xs text-slate-200">
          <p className="font-medium text-cyan-50">Legacy spreadsheet backfill</p>
          <p className="mt-1">
            {snapshot.normalization.legacy_backfill.inserted_metric_count} metrics added across{" "}
            {snapshot.normalization.legacy_backfill.covered_date_count} historical days;{" "}
            {snapshot.normalization.legacy_backfill.conflict_metric_count} conflicts kept the more detailed JSON value.
          </p>
          {snapshot.normalization.legacy_backfill.excluded_sheet_count +
            snapshot.normalization.legacy_backfill.unknown_sheet_count +
            snapshot.normalization.legacy_backfill.ambiguous_cell_count > 0 ? (
            <p className="mt-1 text-amber-100">
              {snapshot.normalization.legacy_backfill.excluded_sheet_count} excluded sheets,{" "}
              {snapshot.normalization.legacy_backfill.unknown_sheet_count} unknown sheets, and{" "}
              {snapshot.normalization.legacy_backfill.ambiguous_cell_count} ambiguous cells were not imported.
            </p>
          ) : null}
        </div>
      ) : null}
      {pollError ? <p className="mt-3 text-xs text-amber-100">{pollError}</p> : null}
      {requeueError ? <p className="mt-3 text-xs text-amber-100">{requeueError}</p> : null}
      {warningCodes.length ? (
        <ul className="mt-3 space-y-1 text-xs text-amber-100">
          {warningCodes.map((code) => <li key={code}>{warningLabel(code)}</li>)}
        </ul>
      ) : null}
      <div className="mt-4 flex flex-wrap gap-2">
        <Link href="/dashboard" className="rounded-full bg-cyan-300 px-4 py-2 text-xs font-semibold text-slate-950 hover:bg-cyan-200">View dashboard</Link>
        <Link href="/account" className="rounded-full border border-white/20 px-4 py-2 text-xs font-medium text-white hover:bg-white/10">View profile</Link>
        {canRequeue ? <button disabled={isRequeueing} type="button" onClick={handleRequeue} className="rounded-full border border-cyan-200/40 px-4 py-2 text-xs font-medium text-cyan-50 disabled:cursor-not-allowed disabled:opacity-50">{isRequeueing ? "Requeueing…" : "Reprocess with latest parser"}</button> : null}
      </div>
      <p className="mt-3 text-xs text-slate-400">Only progress counts and safe warning summaries are shown; source names, paths, and health values are never displayed.</p>
    </section>
  );
}
