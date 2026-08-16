import { redirect } from "next/navigation";

import { DashboardShell, SafeErrorState } from "@/components/dashboard/dashboard-shell";
import { GoalForm } from "@/components/dashboard/goal-form";
import { getGoals } from "@/lib/dashboard/data";
import { GOAL_DEFINITIONS } from "@/lib/dashboard/types";

export const dynamic = "force-dynamic";

export default async function GoalsPage({ searchParams }: { searchParams: Promise<{ saved?: string; error?: string }> }) {
  const result = await getGoals();
  if (result.status === "unauthorized") redirect("/auth/sign-in?error=authentication-required");
  const params = await searchParams;
  if (result.status === "error") return <DashboardShell active="/goals" eyebrow="Goals" title="Goals that fit your routine" description="We could not load your goals right now."><SafeErrorState /></DashboardShell>;
  return <DashboardShell active="/goals" eyebrow="Goal setup" title="Choose a few useful targets" description="Set targets for the habits your imported data can describe. These are personal wellness goals, not clinical prescriptions."><div className="space-y-6"><div className="flex flex-col gap-3">{params.saved ? <p className="rounded-2xl border border-emerald-200/20 bg-emerald-300/10 p-4 text-sm text-emerald-100" role="status">{params.saved === "archived" ? "Goal archived and kept in your history." : "Goal saved."}</p> : null}{params.error ? <p className="rounded-2xl border border-amber-200/20 bg-amber-300/10 p-4 text-sm text-amber-100" role="alert">That goal could not be saved. Check the target and try again.</p> : null}</div><p className="text-sm text-slate-400">Changing a target updates the active goal. Archive it when it no longer applies so the previous goal remains recorded.</p><div className="grid gap-4 lg:grid-cols-2">{GOAL_DEFINITIONS.map((definition) => <GoalForm key={definition.metric} definition={definition} goal={result.data.find((goal) => goal.metric === definition.metric)} />)}</div></div></DashboardShell>;
}
