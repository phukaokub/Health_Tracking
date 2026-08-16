import { redirect } from "next/navigation";

import { AppShell, EmptyState, ErrorState, MetricCards, MetricsTable, PageIntro, WindowLinks } from "@/components/summary/summary-ui";
import { getSummary, type SummarySnapshot, type SummaryWindow } from "@/lib/summary/summary-api";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

function requestedWindow(value?: string): SummaryWindow {
  return value === "28" ? 28 : value === "90" ? 90 : 7;
}

export default async function DashboardPage({ searchParams }: { searchParams: Promise<{ window?: string }> }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/sign-in?error=authentication-required");
  const windowDays = requestedWindow((await searchParams).window);

  let snapshot: SummarySnapshot | null = null;
  try { snapshot = await getSummary(windowDays); } catch { /* Render the safe error state below. */ }
  if (!snapshot) {
    return <AppShell active="dashboard"><div className="mx-auto max-w-6xl px-5 py-12 sm:px-8 sm:py-16"><PageIntro eyebrow="Dashboard" title="Your daily dashboard" description="Compare the last available days at a glance." /><ErrorState /></div></AppShell>;
  }
  return (
    <AppShell active="dashboard">
      <div className="mx-auto max-w-6xl px-5 py-12 sm:px-8 sm:py-16">
        <PageIntro eyebrow="Dashboard" title="Your daily dashboard" description="Compare the last available days at a glance. Missing days stay visible instead of being mistaken for zero." />
        <div className="mt-8 flex flex-wrap items-center justify-between gap-4"><p className="text-sm text-slate-400">Timezone: <span className="text-slate-200">{snapshot.timezone}</span></p><WindowLinks active={windowDays} /></div>
        {snapshot.coverage.days_with_data === 0 && <EmptyState state={snapshot.quality.import_state} />}
        {snapshot.coverage.days_with_data > 0 && <div className="mt-8 grid gap-6"><MetricCards snapshot={snapshot} /><MetricsTable snapshot={snapshot} /></div>}
      </div>
    </AppShell>
  );
}
