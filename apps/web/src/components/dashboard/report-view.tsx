import Link from "next/link";
import { ArrowUpRight, Check, CircleHelp, HeartPulse, Minus, Moon, PersonStanding, ShieldCheck, TrendingDown, TrendingUp } from "lucide-react";

import { saveWellnessSnapshot } from "@/app/actions";
import { REPORT_OPTIONS, type ReportCoverage, type ReportData, type ReportDay, type ReportRange } from "@/lib/dashboard/types";
import type { WellnessScore } from "@/lib/dashboard/scoring";

const coverageLabels: Array<[keyof ReportCoverage, string]> = [
  ["steps", "Steps"],
  ["active_minutes", "Active minutes"],
  ["sleep", "Sleep"],
  ["activity", "Activity"],
  ["workouts", "Workouts"],
  ["heart_rate", "Heart rate"],
];

export function RangeTabs({ range }: { range: ReportRange }) {
  return (
    <div className="flex flex-wrap gap-2" aria-label="Report date range">
      {REPORT_OPTIONS.map((option) => (
        <Link key={option} href={`?range=${option}`} aria-current={range === option ? "page" : undefined} className={`rounded-full px-4 py-2 text-sm ${range === option ? "bg-cyan-300 font-semibold text-slate-950" : "border border-white/15 text-slate-300 hover:bg-white/10"}`}>
          {option === "latest" ? "Latest imported" : `${option} days`}
        </Link>
      ))}
    </div>
  );
}

export function WellnessScoreView({ score }: { score: WellnessScore | null }) {
  if (!score) return null;
  const trendIcon = score.trend.status === "improving" ? <TrendingUp className="size-4" aria-hidden="true" /> : score.trend.status === "declining" ? <TrendingDown className="size-4" aria-hidden="true" /> : <Minus className="size-4" aria-hidden="true" />;
  const totalLabel = score.total === null ? "Insufficient data" : `${Math.round(score.total)} / 100`;
  return <section className="space-y-5 rounded-3xl border border-cyan-200/20 bg-cyan-300/10 p-5 sm:p-6" aria-labelledby="wellness-score-title">
    <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div><div className="flex items-center gap-2 text-cyan-100"><ShieldCheck className="size-5" aria-hidden="true" /><h2 id="wellness-score-title" className="text-sm font-semibold">Explainable wellness score</h2></div><p className="mt-2 text-4xl font-semibold tracking-tight">{totalLabel}</p><p className="mt-2 max-w-2xl text-sm leading-6 text-slate-300">{score.safety}</p></div>
      <div className="rounded-2xl border border-white/10 bg-slate-950/30 px-4 py-3 text-right text-xs text-slate-300"><p>Version {score.version}</p><p className="mt-1">Source: report + active goals</p><p className="mt-1">{formatDate(score.window.start_date)} – {formatDate(score.window.end_date)}</p><p className="mt-1">{score.coverage}% weighted coverage</p><form action={saveWellnessSnapshot} className="mt-3"><button type="submit" className="rounded-full border border-cyan-200/30 px-3 py-1.5 text-xs font-semibold text-cyan-100 hover:bg-cyan-300/10">Save snapshot</button></form></div>
    </div>
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{score.components.map((component) => <article key={component.key} className="rounded-2xl border border-white/10 bg-slate-950/30 p-4"><div className="flex items-start justify-between gap-3"><p className="text-sm font-medium text-white">{component.label}</p><span className="text-xs text-slate-400">{component.weight}%</span></div><p className="mt-3 text-2xl font-semibold">{component.score === null ? "Not scored" : `${Math.round(component.score)}`}</p><p className="mt-1 text-xs text-slate-400">{component.coverage}% covered</p><p className="mt-3 text-xs leading-5 text-slate-300">{component.evidence}</p></article>)}</div>
    <div className="grid gap-4 lg:grid-cols-[0.8fr_1.2fr]"><section className="rounded-2xl border border-white/10 bg-slate-950/30 p-4" aria-labelledby="goal-trend-title"><div className="flex items-center gap-2 text-cyan-100">{trendIcon}<h3 id="goal-trend-title" className="font-semibold">28-day goal trend</h3></div><p className="mt-3 text-lg font-semibold capitalize">{score.trend.status}</p>{score.trend.change !== null ? <p className="mt-1 text-sm text-slate-300">{score.trend.change > 0 ? "+" : ""}{score.trend.change} points from the first to last 14 days.</p> : null}<p className="mt-3 text-xs leading-5 text-slate-400">{score.trend.evidence}</p></section><section className="rounded-2xl border border-white/10 bg-slate-950/30 p-4" aria-labelledby="suggestions-title"><h3 id="suggestions-title" className="font-semibold">What the data suggests</h3>{score.suggestions.length ? <ul className="mt-3 space-y-2 text-sm text-slate-300">{score.suggestions.map((suggestion) => <li key={suggestion.key} className="rounded-xl border border-white/10 px-3 py-2">{suggestion.text}</li>)}</ul> : <p className="mt-3 text-sm text-slate-300">No additional suggestion is needed for this window.</p>}</section></div>
  </section>;
}

export function DashboardView({ report }: { report: ReportData }) {
  const totals = totalsFor(report.days);
  const hasData = report.days.some((day) => day.record_count > 0);
  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 rounded-3xl border border-cyan-200/20 bg-cyan-300/10 p-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-sm text-cyan-100">{formatDate(report.start_date)} – {formatDate(report.end_date)}</p>
          <p className="mt-2 text-xs text-slate-300">Daily grouping uses {report.timezone}. This is a wellness summary, not a medical assessment.</p>
        </div>
        <Link href="/reports" className="inline-flex items-center gap-2 text-sm font-semibold text-cyan-100 hover:text-white">Open detailed reports <ArrowUpRight className="size-4" aria-hidden="true" /></Link>
      </div>
      {!hasData ? <div className="rounded-3xl border border-white/10 bg-white/5 p-6 text-sm text-slate-300">There is no normalized data in this window yet. Try a wider report range or return after an import finishes.</div> : null}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="Average steps" value={formatCompact(totals.steps / Math.max(1, totals.daysWithSteps))} detail={report.coverage.steps ? `${totals.daysWithSteps} days covered` : "Not available"} />
        <MetricCard label="Active minutes" value={formatCompact(totals.activeMinutes)} detail={report.coverage.active_minutes ? "From normalized activity data" : "Not available"} />
        <MetricCard label="Sleep average" value={totals.sleepDays ? `${(totals.sleepHours / totals.sleepDays).toFixed(1)} h` : "—"} detail={report.coverage.sleep ? `${totals.sleepDays} nights covered` : "Not available"} />
        <MetricCard label="Workouts" value={formatCompact(totals.workouts)} detail={report.coverage.workouts ? "Sessions in this window" : "Not available"} />
      </div>
      <div className="grid gap-6 lg:grid-cols-[1.5fr_1fr]">
        <DailyActivityChart days={report.days} />
        <CoveragePanel coverage={report.coverage} />
      </div>
      <div className="grid gap-6 md:grid-cols-3">
        <DetailCard icon={<Moon className="size-5" aria-hidden="true" />} title="Sleep" value={totals.sleepDays ? `${(totals.sleepHours / totals.sleepDays).toFixed(1)} hours average` : "No sleep records in this window"} />
        <DetailCard icon={<PersonStanding className="size-5" aria-hidden="true" />} title="Movement" value={totals.activityMinutes ? `${formatCompact(totals.activityMinutes)} active minutes` : "No activity records in this window"} />
        <DetailCard icon={<HeartPulse className="size-5" aria-hidden="true" />} title="Cardio context" value={totals.averageHeartRate ? `Average heart rate ${Math.round(totals.averageHeartRate)} bpm` : "Heart-rate data is not available"} />
      </div>
    </div>
  );
}

export function ReportsView({ report }: { report: ReportData }) {
  const totals = totalsFor(report.days);
  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 rounded-3xl border border-white/10 bg-white/5 p-5 sm:flex-row sm:items-center sm:justify-between">
        <div><p className="text-sm text-slate-300">Showing {formatDate(report.start_date)} – {formatDate(report.end_date)}</p><p className="mt-1 text-xs text-slate-400">Timezone: {report.timezone}</p></div>
        <Link href="/dashboard" className="text-sm font-semibold text-cyan-200 hover:text-white">Back to dashboard</Link>
      </div>
      <ReportSection title="Sleep" icon={<Moon className="size-5" aria-hidden="true" />} available={report.coverage.sleep}>
        <p className="text-2xl font-semibold">{totals.sleepDays ? `${(totals.sleepHours / totals.sleepDays).toFixed(1)} hours` : "No sleep data"}</p>
        <p className="mt-2 text-sm text-slate-300">Average duration across {totals.sleepDays || 0} covered nights. Sleep sessions are grouped by the local date they ended.</p>
        <DailyTable days={report.days} columns={["date", "sleep_hours"]} />
      </ReportSection>
      <ReportSection title="Activity" icon={<PersonStanding className="size-5" aria-hidden="true" />} available={report.coverage.activity || report.coverage.steps || report.coverage.active_minutes}>
        <div className="grid gap-4 sm:grid-cols-3"><MiniStat label="Steps" value={formatCompact(totals.steps)} /><MiniStat label="Active minutes" value={formatCompact(totals.activeMinutes)} /><MiniStat label="Distance" value={`${(totals.distanceMetres / 1000).toFixed(1)} km`} /></div>
        <DailyTable days={report.days} columns={["date", "steps", "active_minutes", "distance_metres"]} />
      </ReportSection>
      <ReportSection title="Cardio and recovery" icon={<HeartPulse className="size-5" aria-hidden="true" />} available={report.coverage.heart_rate || report.coverage.workouts}>
        <div className="grid gap-4 sm:grid-cols-3"><MiniStat label="Avg heart rate" value={totals.averageHeartRate ? `${Math.round(totals.averageHeartRate)} bpm` : "—"} /><MiniStat label="Workouts" value={formatCompact(totals.workouts)} /><MiniStat label="Workout minutes" value={formatCompact(totals.workoutMinutes)} /></div>
        <DailyTable days={report.days} columns={["date", "average_heart_rate", "workout_count", "workout_minutes"]} />
        <div className="mt-5 flex gap-3 rounded-2xl border border-white/10 bg-slate-950/40 p-4 text-sm text-slate-300"><CircleHelp className="mt-0.5 size-4 shrink-0 text-cyan-200" aria-hidden="true" /><p>ECG waveforms, RRI, and route data are excluded from this first dashboard release. No clinical interpretation is provided.</p></div>
      </ReportSection>
    </div>
  );
}

export function CoveragePanel({ coverage, allTime = false }: { coverage: ReportCoverage; allTime?: boolean }) {
  const available = coverageLabels.filter(([key]) => coverage[key]).length;
  return <section className="rounded-3xl border border-white/10 bg-white/5 p-5" aria-labelledby="coverage-title"><div className="flex items-center justify-between gap-3"><h2 id="coverage-title" className="text-lg font-semibold">Data coverage</h2><span className="text-xs text-slate-400">{available}/{coverageLabels.length} metrics</span></div><p className="mt-2 text-sm text-slate-400">{allTime ? "Across the imported history" : "In this selected window"}</p><ul className="mt-5 space-y-3">{coverageLabels.map(([key, label]) => <li key={key} className="flex items-center justify-between gap-3 text-sm"><span className="text-slate-300">{label}</span><span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs ${coverage[key] ? "bg-emerald-300/15 text-emerald-100" : "bg-white/10 text-slate-400"}`}>{coverage[key] ? <Check className="size-3" aria-hidden="true" /> : null}{coverage[key] ? "Available" : "Not available"}</span></li>)}</ul></section>;
}

function DailyActivityChart({ days }: { days: ReportDay[] }) {
  const max = Math.max(1, ...days.map((day) => day.steps));
  return <section className="rounded-3xl border border-white/10 bg-white/5 p-5" aria-labelledby="activity-chart-title"><div className="flex items-center justify-between gap-3"><div><h2 id="activity-chart-title" className="text-lg font-semibold">Steps by day</h2><p className="mt-1 text-sm text-slate-400">A simple view of the selected window.</p></div><span className="text-xs text-slate-400">{days.length} days</span></div><div className="mt-6 flex h-40 items-end gap-1.5 overflow-hidden" aria-hidden="true">{days.map((day) => <div key={day.date} className="flex min-w-0 flex-1 items-end" title={`${formatDate(day.date)}: ${formatCompact(day.steps)} steps`}><div className="w-full rounded-t-md bg-cyan-300/80" style={{ height: `${Math.max(day.steps ? 4 : 1, (day.steps / max) * 100)}%` }} /></div>)}</div><p className="mt-4 text-xs text-slate-400">Exact values are available in the accessible table below.</p><DailyTable days={days} columns={["date", "steps"]} compact /></section>;
}

function DailyTable({ days, columns, compact = false }: { days: ReportDay[]; columns: Array<keyof ReportDay>; compact?: boolean }) {
  return <div className={`mt-5 overflow-x-auto ${compact ? "max-h-48" : ""}`}><table className="w-full min-w-[360px] text-left text-xs"><thead className="text-slate-500"><tr>{columns.map((column) => <th key={column} className="px-2 py-2 font-medium">{columnLabel(column)}</th>)}</tr></thead><tbody>{days.map((day) => <tr key={day.date} className="border-t border-white/5 text-slate-300">{columns.map((column) => <td key={column} className="px-2 py-2">{columnValue(day, column)}</td>)}</tr>)}</tbody></table></div>;
}

function ReportSection({ title, icon, available, children }: { title: string; icon: React.ReactNode; available: boolean; children: React.ReactNode }) {
  return <section className="rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6"><div className="flex items-center gap-3"><span className="grid size-9 place-items-center rounded-xl bg-cyan-300/15 text-cyan-200">{icon}</span><div><h2 className="text-xl font-semibold">{title}</h2><p className="text-xs text-slate-400">{available ? "Normalized data available" : "Coverage is not available"}</p></div></div>{available ? <div className="mt-6">{children}</div> : <p className="mt-6 rounded-2xl border border-white/10 bg-slate-950/40 p-4 text-sm text-slate-300">There is not enough imported data for this section yet. Missing data is shown explicitly and is not treated as a low result.</p>}</section>;
}

function MetricCard({ label, value, detail }: { label: string; value: string; detail: string }) { return <article className="rounded-3xl border border-white/10 bg-white/5 p-5"><p className="text-sm text-slate-400">{label}</p><p className="mt-3 text-3xl font-semibold tracking-tight">{value}</p><p className="mt-2 text-xs text-slate-400">{detail}</p></article>; }
function DetailCard({ icon, title, value }: { icon: React.ReactNode; title: string; value: string }) { return <article className="rounded-3xl border border-white/10 bg-white/5 p-5"><div className="flex items-center gap-3 text-cyan-200">{icon}<h2 className="font-semibold text-white">{title}</h2></div><p className="mt-4 text-sm leading-6 text-slate-300">{value}</p></article>; }
function MiniStat({ label, value }: { label: string; value: string }) { return <div className="rounded-2xl bg-slate-950/40 p-4"><p className="text-xs text-slate-400">{label}</p><p className="mt-2 text-xl font-semibold">{value}</p></div>; }

function totalsFor(days: ReportDay[]) {
  const withSteps = days.filter((day) => day.steps > 0).length;
  const sleepDays = days.filter((day) => day.sleep_hours > 0).length;
  const total = days.reduce((totals, day) => ({
    steps: totals.steps + day.steps,
    activeMinutes: totals.activeMinutes + day.active_minutes,
    activityMinutes: totals.activityMinutes + day.activity_minutes,
    sleepHours: totals.sleepHours + day.sleep_hours,
    distanceMetres: totals.distanceMetres + day.distance_metres,
    workouts: totals.workouts + day.workout_count,
    workoutMinutes: totals.workoutMinutes + day.workout_minutes,
    averageHeartRate: day.average_heart_rate ? totals.averageHeartRate + day.average_heart_rate : totals.averageHeartRate,
    heartRateDays: day.average_heart_rate ? totals.heartRateDays + 1 : totals.heartRateDays,
  }), { steps: 0, activeMinutes: 0, activityMinutes: 0, sleepHours: 0, distanceMetres: 0, workouts: 0, workoutMinutes: 0, averageHeartRate: 0, heartRateDays: 0 });
  return { ...total, daysWithSteps: withSteps, sleepDays, averageHeartRate: total.heartRateDays ? total.averageHeartRate / total.heartRateDays : 0 };
}

function columnLabel(column: keyof ReportDay): string {
  const labels: Partial<Record<keyof ReportDay, string>> = {
    date: "Day", steps: "Steps", active_minutes: "Active min", calories: "Calories",
    distance_metres: "Distance m", average_heart_rate: "Avg bpm", resting_heart_rate: "Resting bpm",
    sleep_hours: "Sleep h", sleep_session_count: "Sleep sessions", activity_minutes: "Activity min",
    activity_count: "Activities", workout_count: "Workouts", workout_minutes: "Workout min",
    workout_distance_metres: "Workout distance", workout_calories: "Workout calories", record_count: "Records",
  };
  return labels[column] ?? column;
}

function columnValue(day: ReportDay, column: keyof ReportDay): string {
  if (column === "date") return formatDate(day.date);
  if (column === "distance_metres") return formatCompact(day.distance_metres);
  if (column === "average_heart_rate") return day.average_heart_rate ? `${Math.round(day.average_heart_rate)}` : "—";
  if (column === "sleep_hours") return day.sleep_hours ? day.sleep_hours.toFixed(1) : "—";
  return formatCompact(Number(day[column]));
}

function formatDate(value: string): string { return new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(`${value}T12:00:00Z`)); }
function formatCompact(value: number): string { return new Intl.NumberFormat("en", { maximumFractionDigits: 0 }).format(Math.round(value)); }
