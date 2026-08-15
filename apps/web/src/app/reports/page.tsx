import { redirect } from "next/navigation";

import { DashboardShell, SafeErrorState } from "@/components/dashboard/dashboard-shell";
import { RangeTabs, ReportsView, WellnessScoreView } from "@/components/dashboard/report-view";
import { getGoals, getReport } from "@/lib/dashboard/data";
import { calculateWellnessScore } from "@/lib/dashboard/scoring";
import { REPORT_RANGES, type ReportRange } from "@/lib/dashboard/types";

export const dynamic = "force-dynamic";

export default async function ReportsPage({ searchParams }: { searchParams: Promise<{ range?: string; saved?: string; error?: string }> }) {
  const params = await searchParams;
  const range = parseRange(params.range);
  const reportPromise = getReport(range);
  const scoreReportPromise = range === 28 ? reportPromise : getReport(28);
  const [result, scoreReportResult, goalsResult] = await Promise.all([reportPromise, scoreReportPromise, getGoals()]);
  if (result.status === "unauthorized") redirect("/auth/sign-in?error=authentication-required");
  if (scoreReportResult.status === "unauthorized" || goalsResult.status === "unauthorized") redirect("/auth/sign-in?error=authentication-required");
  const score = scoreReportResult.status === "ok" && goalsResult.status === "ok" ? calculateWellnessScore(scoreReportResult.data, goalsResult.data) : null;
  return <DashboardShell active="/reports" eyebrow="Reports" title="Look closer when you want to" description="Switch between short and longer windows to review sleep, activity, and cardio sections with the same timezone and coverage rules as the dashboard."><div className="space-y-6"><RangeTabs range={range} />{params.saved === "snapshot" ? <p className="rounded-2xl border border-emerald-200/20 bg-emerald-300/10 p-4 text-sm text-emerald-100" role="status">This score version was saved as an owner-only snapshot.</p> : null}{params.error === "snapshot-save" ? <p className="rounded-2xl border border-amber-200/20 bg-amber-300/10 p-4 text-sm text-amber-100" role="alert">The score snapshot could not be saved. The report itself is still available.</p> : null}<WellnessScoreView score={score} />{result.status === "error" ? <SafeErrorState /> : <ReportsView report={result.data} />}</div></DashboardShell>;
}

function parseRange(value: string | undefined): ReportRange { const parsed = Number(value); return REPORT_RANGES.includes(parsed as ReportRange) ? parsed as ReportRange : 28; }
