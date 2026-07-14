import {
  Activity,
  Bell,
  ChevronDown,
  Footprints,
  HeartPulse,
  MoonStar,
  Sparkles,
} from "lucide-react";

const weeklyActivity = [42, 58, 48, 72, 64, 82, 68];

function MetricCard({
  icon,
  label,
  value,
  detail,
  accent,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  detail: string;
  accent: string;
}) {
  return (
    <article className="rounded-2xl border border-slate-100 bg-white p-4 shadow-[0_12px_30px_-24px_rgba(15,23,42,0.55)]">
      <div className="flex items-center justify-between">
        <span className={"grid size-8 place-items-center rounded-xl " + accent}>{icon}</span>
        <span className="text-xs font-medium text-emerald-600">{detail}</span>
      </div>
      <p className="mt-4 text-xs font-medium text-slate-500">{label}</p>
      <p className="mt-1 text-xl font-semibold tracking-tight text-slate-950">{value}</p>
    </article>
  );
}

export function ReportPreview() {
  return (
    <section
      id="sample-report"
      aria-label="Example wellness report dashboard"
      className="overflow-hidden rounded-[2rem] border border-white/80 bg-slate-50 p-2 shadow-[0_32px_100px_-28px_rgba(8,47,73,0.65)]"
    >
      <div className="overflow-hidden rounded-[1.55rem] bg-slate-50">
        <header className="flex items-center justify-between border-b border-slate-200 bg-white px-4 py-3 sm:px-5">
          <div className="flex items-center gap-2">
            <span className="grid size-7 place-items-center rounded-lg bg-slate-950 text-white">
              <HeartPulse className="size-4" aria-hidden="true" />
            </span>
            <span className="text-sm font-semibold tracking-tight text-slate-900">
              Health Tracking
            </span>
          </div>
          <div className="flex items-center gap-2">
            <span className="hidden text-xs font-medium text-slate-500 sm:inline">28 Jun — 4 Jul</span>
            <Bell className="size-4 text-slate-400" aria-hidden="true" />
            <span className="grid size-7 place-items-center rounded-full bg-gradient-to-br from-teal-200 to-sky-300 text-[10px] font-semibold text-slate-800">
              TK
            </span>
          </div>
        </header>

        <div className="grid min-h-[430px] grid-cols-[48px_1fr] sm:grid-cols-[126px_1fr]">
          <aside className="flex flex-col items-center gap-5 border-r border-slate-200 bg-white py-5 sm:items-stretch sm:px-3">
            <span className="hidden px-2 text-[10px] font-semibold uppercase tracking-[0.18em] text-slate-400 sm:block">
              Overview
            </span>
            <div className="grid place-items-center rounded-xl bg-slate-950 p-2 text-white sm:flex sm:gap-2">
              <Activity className="size-4" aria-hidden="true" />
              <span className="hidden text-xs font-medium sm:inline">Today</span>
            </div>
            <div className="grid place-items-center p-2 text-slate-400 sm:flex sm:gap-2">
              <Sparkles className="size-4" aria-hidden="true" />
              <span className="hidden text-xs font-medium sm:inline">Insights</span>
            </div>
            <div className="grid place-items-center p-2 text-slate-400 sm:flex sm:gap-2">
              <HeartPulse className="size-4" aria-hidden="true" />
              <span className="hidden text-xs font-medium sm:inline">Trends</span>
            </div>
          </aside>

          <div className="min-w-0 p-4 sm:p-5">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-xs font-medium text-slate-500">Good morning, Teerawat</p>
                <h2 className="mt-1 text-xl font-semibold tracking-tight text-slate-950">
                  Your week at a glance
                </h2>
              </div>
              <button className="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-600">
                Week <ChevronDown className="size-3" aria-hidden="true" />
              </button>
            </div>

            <div className="mt-4 grid gap-3 sm:grid-cols-[1.14fr_0.86fr]">
              <article className="rounded-2xl bg-slate-950 p-4 text-white shadow-sm">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-xs font-medium text-slate-300">Wellness score</p>
                    <p className="mt-1 text-4xl font-semibold tracking-tight">84</p>
                    <p className="mt-1 text-xs text-slate-300">Balanced · 6-day trend</p>
                  </div>
                  <div
                    className="grid size-14 place-items-center rounded-full"
                    style={{
                      background:
                        "conic-gradient(#67e8f9 0deg 302deg, rgba(255,255,255,0.18) 302deg 360deg)",
                    }}
                  >
                    <div className="grid size-10 place-items-center rounded-full bg-slate-950 text-xs font-semibold">
                      84%
                    </div>
                  </div>
                </div>
                <div className="mt-4 flex h-9 items-end gap-1">
                  {weeklyActivity.map((height, index) => (
                    <span
                      key={height}
                      className={index === 5 ? "flex-1 rounded-t bg-cyan-300" : "flex-1 rounded-t bg-slate-700"}
                      style={{ height: height + "%" }}
                    />
                  ))}
                </div>
              </article>

              <article className="rounded-2xl bg-gradient-to-br from-cyan-50 to-sky-100 p-4">
                <div className="flex items-center justify-between">
                  <span className="grid size-8 place-items-center rounded-xl bg-white text-sky-600 shadow-sm">
                    <MoonStar className="size-4" aria-hidden="true" />
                  </span>
                  <span className="text-xs font-medium text-sky-700">+18m vs avg</span>
                </div>
                <p className="mt-4 text-xs font-medium text-slate-500">Sleep</p>
                <p className="mt-1 text-xl font-semibold tracking-tight text-slate-950">7h 42m</p>
                <div className="mt-3 flex h-2 overflow-hidden rounded-full bg-white/90">
                  <span className="w-[43%] bg-indigo-400" />
                  <span className="w-[34%] bg-sky-400" />
                  <span className="w-[23%] bg-cyan-200" />
                </div>
              </article>
            </div>

            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              <MetricCard
                icon={<Footprints className="size-4" aria-hidden="true" />}
                label="Steps"
                value="8,650"
                detail="76% of goal"
                accent="bg-amber-100 text-amber-700"
              />
              <MetricCard
                icon={<Activity className="size-4" aria-hidden="true" />}
                label="Active minutes"
                value="42 min"
                detail="+12 min"
                accent="bg-emerald-100 text-emerald-700"
              />
            </div>

            <article className="mt-3 rounded-2xl border border-slate-100 bg-white p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs font-medium text-slate-500">Today’s focus</p>
                  <p className="mt-1 text-sm font-semibold text-slate-900">
                    Protect your evening wind-down
                  </p>
                </div>
                <span className="rounded-full bg-teal-50 px-2.5 py-1 text-xs font-medium text-teal-700">
                  On track
                </span>
              </div>
              <p className="mt-2 text-xs leading-5 text-slate-500">
                Your bedtime consistency is improving. A 22:45 wind-down keeps you close to this week’s sleep goal.
              </p>
            </article>
          </div>
        </div>
      </div>
    </section>
  );
}
