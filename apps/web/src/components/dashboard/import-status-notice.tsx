import Link from "next/link";

import type { LatestImport } from "@/lib/dashboard/types";

export function ImportStatusNotice({ importData }: { importData: Pick<LatestImport, "state" | "job_state" | "parser_version_target"> | null }) {
  const pending = Boolean(importData && (["uploading", "uploaded", "queued", "processing"].includes(importData.state)
    || ["leased", "queued", "processing"].includes(importData.job_state ?? "")));
  if (!importData || !pending) return null;

  const label = importData.state === "processing" || importData.job_state === "processing"
    ? "Your latest import is being processed."
    : "Your latest import is queued for processing.";
  const target = importData.parser_version_target ? ` Parser target: ${importData.parser_version_target}.` : "";
  return (
    <p className="rounded-2xl border border-cyan-200/20 bg-cyan-300/10 p-4 text-sm text-cyan-50" role="status">
      {label} The dashboard and reports continue to show the last completed normalized data until this run finishes.{target} {" "}
      <Link href="/import" className="font-semibold underline decoration-cyan-200/50 underline-offset-4 hover:text-white">View import status</Link>.
    </p>
  );
}
