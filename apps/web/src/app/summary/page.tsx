import { redirect } from "next/navigation";

import { AppShell, EmptyState, ErrorState, MetricCards, PageIntro, QualityCard, WindowLinks } from "@/components/summary/summary-ui";
import { getSummary, type SummarySnapshot, type SummaryWindow } from "@/lib/summary/summary-api";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

function requestedWindow(value?: string): SummaryWindow {
  return value === "28" ? 28 : value === "90" ? 90 : 7;
}

export default async function SummaryPage({ searchParams }: { searchParams: Promise<{ window?: string }> }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/sign-in?error=authentication-required");
  const windowDays = requestedWindow((await searchParams).window);

  let snapshot: SummarySnapshot | null = null;
  try { snapshot = await getSummary(windowDays); } catch { /* Render the safe error state below. */ }
  if (!snapshot) {
    return <AppShell active="summary"><div className="mx-auto max-w-6xl px-5 py-12 sm:px-8 sm:py-16"><PageIntro eyebrow="First summary" title="Your imported picture" description="A calm view of what arrived, what is covered, and where the gaps are." /><ErrorState /></div></AppShell>;
  }
  const hasData = snapshot.coverage.days_with_data > 0;
  return (
    <AppShell active="summary">
      <div className="mx-auto max-w-6xl px-5 py-12 sm:px-8 sm:py-16">
        <PageIntro eyebrow="First summary" title="Your imported picture" description="A calm view of what arrived, what is covered, and where the gaps are. This is a wellness summary, not a medical interpretation." />
        <div className="mt-8 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-white/10 bg-slate-900/70 p-4 text-sm text-slate-300"><span>{snapshot.coverage.first_day ? `Available from ${snapshot.coverage.first_day} to ${snapshot.coverage.last_day}` : "No normalized days yet"}</span><WindowLinks active={windowDays} /></div>
        {!hasData && <EmptyState state={snapshot.quality.import_state} />}
        {hasData && <div className="mt-8 grid gap-6"><QualityCard snapshot={snapshot} /><MetricCards snapshot={snapshot} /></div>}
      </div>
    </AppShell>
  );
}
