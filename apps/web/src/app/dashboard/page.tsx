import { redirect } from "next/navigation";

import { DashboardShell, SafeErrorState } from "@/components/dashboard/dashboard-shell";
import { ImportStatusNotice } from "@/components/dashboard/import-status-notice";
import { DashboardView, RangeTabs } from "@/components/dashboard/report-view";
import { getLatestImportStatus, getReport } from "@/lib/dashboard/data";
import { REPORT_RANGES, type ReportRange } from "@/lib/dashboard/types";

export const dynamic = "force-dynamic";

export default async function DashboardPage({ searchParams }: { searchParams: Promise<{ range?: string }> }) {
  const params = await searchParams;
  const range = parseRange(params.range);
  const [result, importStatus] = await Promise.all([getReport(range), getLatestImportStatus()]);
  if (result.status === "unauthorized") redirect("/auth/sign-in?error=authentication-required");
  if (importStatus.status === "unauthorized") redirect("/auth/sign-in?error=authentication-required");
  return <DashboardShell active="/dashboard" eyebrow="Dashboard" title="Your current wellness picture" description="Use the dashboard for a quick view of movement, sleep, and cardio context. Missing data stays visible instead of becoming a misleading zero."><div className="space-y-6"><ImportStatusNotice importData={importStatus.status === "ok" ? importStatus.data : null} /><RangeTabs range={range} />{result.status === "error" ? <SafeErrorState /> : <DashboardView report={result.data} />}</div></DashboardShell>;
}

function parseRange(value: string | undefined): ReportRange {
  if (value === "latest") return "latest";
  const parsed = Number(value);
  return REPORT_RANGES.includes(parsed as (typeof REPORT_RANGES)[number]) ? parsed as (typeof REPORT_RANGES)[number] : 7;
}
