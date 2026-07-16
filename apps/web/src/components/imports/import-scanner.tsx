"use client";

import { useEffect, useRef, useState } from "react";

import { DirectoryScanner } from "@/lib/imports/directory-scanner";
import type { DirectoryScanInput, DirectoryScanResult } from "@/lib/imports/scanner.types";

export function ImportScanner() {
  const inputRef = useRef<HTMLInputElement>(null);
  const scannerRef = useRef<DirectoryScanner | null>(null);
  const [progress, setProgress] = useState<{ completedFiles: number; totalFiles: number } | null>(null);
  const [result, setResult] = useState<DirectoryScanResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    scannerRef.current = new DirectoryScanner();
    return () => scannerRef.current?.dispose();
  }, []);

  function chooseDirectory() {
    inputRef.current?.setAttribute("webkitdirectory", "");
    inputRef.current?.setAttribute("directory", "");
    inputRef.current?.click();
  }

  async function scanSelection(event: React.ChangeEvent<HTMLInputElement>) {
    const entries: DirectoryScanInput[] = Array.from(event.target.files ?? []).map((file) => {
      const relativePath = (file as File & { webkitRelativePath?: string }).webkitRelativePath || file.name;
      return { file, relativePath };
    });
    event.target.value = "";
    if (!entries.length || !scannerRef.current) return;

    setError(null);
    setResult(null);
    setProgress({ completedFiles: 0, totalFiles: entries.length });
    try {
      setResult(await scannerRef.current.scan(entries, setProgress));
    } catch (scanError) {
      setError(scanError instanceof Error ? scanError.message : "scan_failed");
    } finally {
      setProgress(null);
    }
  }

  const planned = result?.files.filter((file) => file.inclusionState === "planned").length ?? 0;
  const excluded = result?.files.filter((file) => file.inclusionState === "excluded").length ?? 0;

  return (
    <section className="rounded-3xl border border-white/10 bg-white/10 p-6">
      <h1 className="text-3xl font-semibold">Review a local health export</h1>
      <p className="mt-3 text-slate-300">
        Select a folder to classify supported files and calculate local checksums. Nothing is uploaded in this review step.
      </p>
      <input ref={inputRef} className="sr-only" type="file" multiple onChange={scanSelection} />
      <button className="mt-6 rounded-full bg-white px-5 py-2 text-sm font-semibold text-slate-950" type="button" onClick={chooseDirectory}>
        Choose export folder
      </button>
      {progress ? <p className="mt-4 text-sm text-slate-300">Reviewing {progress.completedFiles} of {progress.totalFiles} files…</p> : null}
      {error ? <p className="mt-4 text-sm text-red-200">Unable to review this selection ({error}).</p> : null}
      {result ? (
        <div className="mt-6 rounded-2xl bg-slate-900/70 p-4 text-sm text-slate-200">
          <p><span className="font-medium text-white">{planned}</span> files prepared for a later upload step; <span className="font-medium text-white">{excluded}</span> excluded.</p>
          {result.warnings.length ? <p className="mt-2 text-amber-200">Some entries were ignored because their path or size policy was unsafe.</p> : null}
          <p className="mt-3 text-slate-400">Names, paths, file contents, and health values are not displayed or sent from this page.</p>
        </div>
      ) : null}
    </section>
  );
}
