import { redirect } from "next/navigation";

import { saveTimezone } from "@/app/actions";
import { DashboardShell, EmptyState, SafeErrorState } from "@/components/dashboard/dashboard-shell";
import { ImportStatusNotice } from "@/components/dashboard/import-status-notice";
import { CoveragePanel } from "@/components/dashboard/report-view";
import { getSummaryData, isImportPending } from "@/lib/dashboard/data";

export const dynamic = "force-dynamic";

export default async function SummaryPage({ searchParams }: { searchParams: Promise<{ saved?: string; error?: string }> }) {
  const result = await getSummaryData();
  if (result.status === "unauthorized") redirect("/auth/sign-in?error=authentication-required");
  if (result.status === "error") return <DashboardShell active="/summary" eyebrow="First summary" title="Your imported picture" description="We could not load the summary right now."><SafeErrorState /></DashboardShell>;
  const { data } = result;
  const params = await searchParams;
  const importData = data.latestImport;
  const pending = isImportPending(importData);
  return <DashboardShell active="/summary" eyebrow="First summary" title="A clear starting point for your wellness data" description="Review what arrived, confirm the timezone used for daily grouping, and see which normalized metrics are ready for your reports.">
    <div className="space-y-6">
      {params.saved === "timezone" ? <Notice tone="success">Timezone saved. Your daily summaries now use {data.timezone}.</Notice> : null}
      {params.error ? <Notice tone="error">That change could not be saved. Check the value and try again.</Notice> : null}
      {!importData ? <EmptyState title="No completed import yet" description="Once a Huawei Health import finishes, this page will show its date range, coverage, and safe processing summary." /> : <>
        <ImportStatusNotice importData={importData} />
        <section className="grid gap-4 sm:grid-cols-3"><SummaryCard label="Imported files" value={String(importData.total_file_count)} detail={pending ? "Latest import queued" : importData.state === "completed_with_warnings" ? "Completed with warnings" : "Completed"} /><SummaryCard label="Normalized records" value={String(importData.normalized_record_count)} detail={pending ? "Waiting for worker" : "Ready for private reports"} /><SummaryCard label="Imported range" value={formatRange(data.report.available_range.start_date, data.report.available_range.end_date)} detail={pending ? "Last completed normalized data" : "Across normalized data"} /></section>
        <div className="grid gap-6 lg:grid-cols-[1.25fr_0.75fr]"><section className="rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6"><h2 className="text-xl font-semibold">Timezone confirmation</h2><p className="mt-2 text-sm leading-6 text-slate-300">Daily values are grouped using the selected timezone. Confirm it before reading weekly patterns.</p><form action={saveTimezone} className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-end"><div className="flex-1"><label htmlFor="timezone" className="text-xs font-medium text-slate-300">IANA timezone</label><input id="timezone" name="timezone" defaultValue={data.timezone} required className="mt-2 w-full rounded-2xl border border-white/15 bg-slate-950/70 px-4 py-3 text-white outline-none focus:border-cyan-300 focus:ring-2 focus:ring-cyan-300/30" /></div><button type="submit" className="rounded-full bg-white px-5 py-3 text-sm font-semibold text-slate-950 hover:bg-slate-100">Confirm timezone</button></form>{data.timezoneCandidate && data.timezoneCandidate !== data.timezone ? <p className="mt-3 text-xs text-amber-100">The import suggested {data.timezoneCandidate}; your profile currently uses {data.timezone}.</p> : null}</section><CoveragePanel coverage={data.report.all_time_coverage} allTime /></div>
        <section className="grid gap-6 md:grid-cols-2"><SummaryList title="Source summary" items={importData.source_families.length ? importData.source_families.map(sourceLabel) : ["Normalized source metadata only"]} /><SummaryList title="Import notes" items={importData.warnings.length ? importData.warnings.map(warningLabel) : ["No processing warnings were recorded"]} /></section>
        {importData.legacy_quality ? <section className="rounded-3xl border border-white/10 bg-white/5 p-5 text-sm text-slate-300"><h2 className="font-semibold text-white">Legacy spreadsheet backfill</h2><p className="mt-2">{importData.legacy_quality.inserted_metric_count} historical metrics were added; {importData.legacy_quality.conflict_metric_count} granular values took precedence.</p><p className="mt-2 text-xs text-slate-400">Excluded sheets: {importData.legacy_quality.excluded_sheet_count} · Unknown sheets: {importData.legacy_quality.unknown_sheet_count} · Ambiguous cells: {importData.legacy_quality.ambiguous_cell_count}</p></section> : null}
      </>}
    </div>
  </DashboardShell>;
}

function SummaryCard({ label, value, detail }: { label: string; value: string; detail: string }) { return <article className="rounded-3xl border border-white/10 bg-white/5 p-5"><p className="text-xs uppercase tracking-[0.15em] text-slate-400">{label}</p><p className="mt-3 text-2xl font-semibold">{value}</p><p className="mt-2 text-xs text-slate-400">{detail}</p></article>; }
function SummaryList({ title, items }: { title: string; items: string[] }) { return <section className="rounded-3xl border border-white/10 bg-white/5 p-5"><h2 className="font-semibold">{title}</h2><ul className="mt-4 space-y-2 text-sm text-slate-300">{items.map((item) => <li key={item} className="rounded-2xl bg-slate-950/40 px-4 py-3">{item}</li>)}</ul></section>; }
function Notice({ tone, children }: { tone: "success" | "error"; children: React.ReactNode }) { return <p className={`rounded-2xl border p-4 text-sm ${tone === "success" ? "border-emerald-200/20 bg-emerald-300/10 text-emerald-100" : "border-amber-200/20 bg-amber-300/10 text-amber-100"}`} role="status">{children}</p>; }
function formatRange(start: string | null, end: string | null) { return start && end ? `${formatDate(start)} – ${formatDate(end)}` : "Not available"; }
function formatDate(value: string) { return new Intl.DateTimeFormat("en", { month: "short", year: "numeric" }).format(new Date(`${value}T12:00:00Z`)); }
function sourceLabel(value: string) { return value === "legacy-xls" || value === "huawei_legacy_xls" ? "Legacy Huawei spreadsheet" : value === "huawei_health_json" ? "Huawei Health JSON" : "Normalized health source"; }
function warningLabel(value: string) { return value.replaceAll("_", " "); }
