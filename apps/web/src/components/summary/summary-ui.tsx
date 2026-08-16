import Link from "next/link";

import type { SummarySnapshot, SummaryWindow } from "@/lib/summary/summary-api";

const navItems = [
	["dashboard", "Dashboard", "/dashboard"],
	["summary", "Summary", "/summary"],
	["reports", "Reports", "/reports"],
	["import", "Import", "/import"],
	["account", "Profile", "/account"],
] as const;

export function AppShell({
  active,
  children,
}: {
  active: (typeof navItems)[number][0];
  children: React.ReactNode;
}) {
  return (
    <main className="min-h-screen bg-slate-950 text-white">
      <header className="border-b border-white/10 bg-slate-950/95">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-5 py-5 sm:px-8">
          <Link href="/dashboard" className="flex items-center gap-3 text-sm font-semibold tracking-tight">
            <span className="grid size-9 place-items-center rounded-xl bg-cyan-300 text-slate-950">∿</span>
            Health Tracking
          </Link>
          <nav className="order-3 flex w-full items-center gap-1 overflow-x-auto rounded-full border border-white/10 bg-white/5 p-1 text-sm sm:order-none sm:w-auto" aria-label="Wellness views">
            {navItems.map(([key, label, href]) => (
              <Link
                key={key}
                href={href}
                aria-current={active === key ? "page" : undefined}
                className={`rounded-full px-3 py-2 transition sm:px-4 ${active === key ? "bg-white text-slate-950" : "text-slate-300 hover:bg-white/10 hover:text-white"}`}
              >
                {label}
              </Link>
            ))}
          </nav>
          <Link href="/account" className="rounded-full border border-white/15 px-4 py-2 text-sm font-medium text-slate-200 transition hover:border-white/35 hover:bg-white/10 hover:text-white">Profile</Link>
        </div>
      </header>
      {children}
    </main>
  );
}

export function PageIntro({ eyebrow, title, description }: { eyebrow: string; title: string; description: string }) {
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.22em] text-cyan-300">{eyebrow}</p>
      <h1 className="mt-3 text-4xl font-semibold tracking-[-0.05em] sm:text-5xl">{title}</h1>
      <p className="mt-4 max-w-2xl text-base leading-7 text-slate-300">{description}</p>
    </div>
  );
}

export function ErrorState() {
  return (
    <section className="mt-10 rounded-3xl border border-amber-300/30 bg-amber-300/10 p-6 text-amber-100">
      <h2 className="text-lg font-semibold">This report could not load right now.</h2>
      <p className="mt-2 text-sm text-amber-100/80">Please try again shortly. Your imported data has not been changed.</p>
    </section>
  );
}

export function EmptyState({ state }: { state: string }) {
  const isEmpty = state === "empty";
  return (
    <section className="mt-10 rounded-3xl border border-cyan-300/20 bg-slate-900/80 p-6">
      <p className="text-xs font-semibold uppercase tracking-[0.18em] text-cyan-300">{isEmpty ? "Waiting for your first import" : "Partial coverage"}</p>
      <h2 className="mt-3 text-2xl font-semibold">There is not enough normalized data for a full picture yet.</h2>
      <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-300">You can still use the available coverage below. Re-run processing or import another export when you are ready.</p>
      <div className="mt-5 flex flex-wrap gap-3">
        <Link href="/import" className="inline-flex rounded-full bg-cyan-300 px-5 py-2.5 text-sm font-semibold text-slate-950 hover:bg-cyan-200">Import more data</Link>
        <Link href="/account" className="inline-flex rounded-full border border-white/20 px-5 py-2.5 text-sm font-medium text-white hover:bg-white/10">Open profile</Link>
      </div>
    </section>
  );
}

function formatNumber(value: number) {
  return new Intl.NumberFormat("en-US").format(value);
}

function formatMinutes(value: number) {
  if (!value) return "—";
  const hours = Math.floor(value / 60);
  const minutes = value % 60;
  return hours ? `${hours}h ${minutes}m` : `${minutes}m`;
}

export function WindowLinks({ active }: { active: SummaryWindow }) {
  return (
    <div className="flex flex-wrap gap-2" aria-label="Report window">
      {[7, 28, 90].map((days) => (
        <Link key={days} href={`?window=${days}`} className={`rounded-full border px-4 py-2 text-sm ${active === days ? "border-cyan-300 bg-cyan-300 text-slate-950" : "border-white/15 text-slate-300 hover:border-white/35"}`}>
          {days} days
        </Link>
      ))}
    </div>
  );
}

export function QualityCard({ snapshot }: { snapshot: SummarySnapshot }) {
  const { quality } = snapshot;
  return (
    <section className="rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-400">Data quality</p>
          <h2 className="mt-2 text-2xl font-semibold capitalize">{quality.import_state.replaceAll("_", " ")}</h2>
        </div>
        <span className="rounded-full bg-emerald-300/15 px-3 py-1 text-xs font-medium text-emerald-200">Private, owner-only</span>
      </div>
      <dl className="mt-6 grid grid-cols-2 gap-4 text-sm sm:grid-cols-4">
        <div><dt className="text-slate-400">Verified files</dt><dd className="mt-1 text-xl font-semibold">{formatNumber(quality.verified_file_count)}</dd></div>
        <div><dt className="text-slate-400">Skipped duplicates</dt><dd className="mt-1 text-xl font-semibold">{formatNumber(quality.skipped_duplicate_file_count)}</dd></div>
        <div><dt className="text-slate-400">Normalized rows</dt><dd className="mt-1 text-xl font-semibold">{formatNumber(quality.normalized_record_count)}</dd></div>
        <div><dt className="text-slate-400">Warnings</dt><dd className="mt-1 text-xl font-semibold">{formatNumber(quality.warning_codes.length)}</dd></div>
      </dl>
      <div className="mt-5 flex flex-wrap gap-2 text-xs text-slate-300">
        <span className="rounded-full bg-slate-900 px-3 py-1.5">Timezone: {snapshot.timezone}</span>
        {quality.source_families.map((source) => <span key={source} className="rounded-full bg-slate-900 px-3 py-1.5">Source: {source.replaceAll("_", " ")}</span>)}
        {quality.warning_codes.map((warning) => <span key={warning} className="rounded-full bg-amber-300/10 px-3 py-1.5 text-amber-100">{warning.replaceAll("_", " ")}</span>)}
      </div>
    </section>
  );
}

export function MetricCards({ snapshot }: { snapshot: SummarySnapshot }) {
  const available = snapshot.metrics.filter((metric) => metric.data_available);
  const totalSteps = available.reduce((sum, metric) => sum + metric.steps, 0);
  const totalActive = available.reduce((sum, metric) => sum + metric.active_minutes, 0);
  const totalSleep = available.reduce((sum, metric) => sum + metric.sleep_minutes, 0);
  const totalWorkouts = available.reduce((sum, metric) => sum + metric.workouts, 0);
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {[
        ["Steps", formatNumber(totalSteps), "total in window"],
        ["Active time", formatMinutes(totalActive), "total in window"],
        ["Sleep", formatMinutes(totalSleep), "recorded sessions"],
        ["Workouts", formatNumber(totalWorkouts), "recorded sessions"],
      ].map(([label, value, note]) => (
        <section key={label} className="rounded-3xl border border-white/10 bg-white/5 p-5">
          <p className="text-sm text-slate-400">{label}</p>
          <p className="mt-3 text-3xl font-semibold tracking-tight">{value}</p>
          <p className="mt-2 text-xs text-slate-500">{note}</p>
        </section>
      ))}
    </div>
  );
}

export function MetricsTable({ snapshot }: { snapshot: SummarySnapshot }) {
  return (
    <div className="overflow-x-auto rounded-3xl border border-white/10 bg-white/5">
      <table className="w-full min-w-[680px] text-left text-sm">
        <caption className="sr-only">Daily wellness summary</caption>
        <thead className="border-b border-white/10 text-xs uppercase tracking-[0.14em] text-slate-400">
          <tr><th className="px-5 py-4 font-medium">Day</th><th className="px-5 py-4 font-medium">Steps</th><th className="px-5 py-4 font-medium">Active</th><th className="px-5 py-4 font-medium">Sleep</th><th className="px-5 py-4 font-medium">Workouts</th><th className="px-5 py-4 font-medium">Heart-rate samples</th></tr>
        </thead>
        <tbody className="divide-y divide-white/5">
          {snapshot.metrics.map((metric) => (
            <tr key={metric.day} className={metric.data_available ? "" : "text-slate-500"}>
              <th scope="row" className="px-5 py-4 font-medium text-slate-200">{metric.day}</th>
              <td className="px-5 py-4">{metric.data_available ? formatNumber(metric.steps) : "—"}</td>
              <td className="px-5 py-4">{metric.data_available ? formatMinutes(metric.active_minutes) : "—"}</td>
              <td className="px-5 py-4">{metric.data_available ? formatMinutes(metric.sleep_minutes) : "—"}</td>
              <td className="px-5 py-4">{metric.data_available ? metric.workouts : "—"}</td>
              <td className="px-5 py-4">{metric.data_available ? formatNumber(metric.heart_rate_samples) : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
