import { archiveGoal, saveGoal } from "@/app/actions";
import type { Goal } from "@/lib/dashboard/types";

export function GoalForm({ definition, goal }: { definition: { metric: string; label: string; unit: string; cadence: string; helper: string; inputStep: string; inputMin: string; inputMax: string }; goal?: Goal }) {
  return (
    <article className="rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-6">
      <div className="flex flex-col gap-1 sm:flex-row sm:items-start sm:justify-between"><div><h2 className="text-lg font-semibold">{definition.label}</h2><p className="mt-1 text-sm text-slate-400">{definition.helper}</p></div><span className="rounded-full bg-white/10 px-3 py-1 text-xs text-slate-300">{definition.cadence}</span></div>
      <form action={saveGoal} className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-end">
        <input type="hidden" name="metric" value={definition.metric} />
        <div className="flex-1"><label htmlFor={`goal-${definition.metric}`} className="text-xs font-medium text-slate-300">Target ({definition.unit})</label><input id={`goal-${definition.metric}`} name="target" type="number" min={definition.inputMin} max={definition.inputMax} step={definition.inputStep} defaultValue={goal?.target || ""} required className="mt-2 w-full rounded-2xl border border-white/15 bg-slate-950/70 px-4 py-3 text-white outline-none focus:border-cyan-300 focus:ring-2 focus:ring-cyan-300/30" /></div>
        <button type="submit" className="rounded-full bg-cyan-300 px-5 py-3 text-sm font-semibold text-slate-950 hover:bg-cyan-200">{goal ? "Update goal" : "Set goal"}</button>
      </form>
      {goal ? <div className="mt-4 flex items-center justify-between gap-3 text-xs text-slate-400"><span>Active since {goal.started_on || "this import"}</span><form action={archiveGoal}><input type="hidden" name="goal_id" value={goal.id} /><button type="submit" className="text-amber-200 hover:text-amber-100">Archive goal</button></form></div> : null}
    </article>
  );
}
