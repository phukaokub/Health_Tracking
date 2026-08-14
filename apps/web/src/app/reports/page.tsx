import { redirect } from "next/navigation";

import { DashboardShell, SafeErrorState } from "@/components/dashboard/dashboard-shell";
import { RangeTabs, ReportsView } from "@/components/dashboard/report-view";
import { getReport } from "@/lib/dashboard/data";
import { REPORT_RANGES, type ReportRange } from "@/lib/dashboard/types";

export const dynamic = "force-dynamic";

export default async function ReportsPage({ searchParams }: { searchParams: Promise<{ range?: string }> }) {
  const params = await searchParams;
  const range = parseRange(params.range);
  const result = await getReport(range);
  if (result.status === "unauthorized") redirect("/auth/sign-in?error=authentication-required");
  return <DashboardShell active="/reports" eyebrow="Reports" title="Look closer when you want to" description="Switch between short and longer windows to review sleep, activity, and cardio sections with the same timezone and coverage rules as the dashboard."><div className="space-y-6"><RangeTabs range={range} />{result.status === "error" ? <SafeErrorState /> : <ReportsView report={result.data} />}</div></DashboardShell>;
}

function parseRange(value: string | undefined): ReportRange { const parsed = Number(value); return REPORT_RANGES.includes(parsed as ReportRange) ? parsed as ReportRange : 28; }
