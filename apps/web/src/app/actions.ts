"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

import { GOAL_DEFINITIONS, type GoalMetric } from "@/lib/dashboard/types";

const goalDefinitionByMetric = new Map(GOAL_DEFINITIONS.map((definition) => [definition.metric, definition]));

export async function saveTimezone(formData: FormData) {
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getUser();
  if (!authData.user) redirect("/auth/sign-in?error=authentication-required");

  const timezone = stringValue(formData.get("timezone"));
  if (!timezone || !isValidTimeZone(timezone)) redirect("/summary?error=invalid-timezone");

  const { error } = await supabase
    .from("profiles")
    .update({ timezone })
    .eq("id", authData.user.id);
  if (error) redirect("/summary?error=timezone-save");

  revalidatePath("/summary");
  revalidatePath("/dashboard");
  revalidatePath("/reports");
  redirect("/summary?saved=timezone");
}

export async function saveGoal(formData: FormData) {
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getUser();
  if (!authData.user) redirect("/auth/sign-in?error=authentication-required");

  const metric = stringValue(formData.get("metric")) as GoalMetric;
  const definition = goalDefinitionByMetric.get(metric);
  const target = numberValue(formData.get("target"));
  if (!definition || !Number.isFinite(target) || target < Number(definition.inputMin) || target > Number(definition.inputMax)) {
    redirect("/goals?error=invalid-goal");
  }

  const { data: existing, error: lookupError } = await supabase
    .from("goals")
    .select("id")
    .eq("metric", metric)
    .eq("active", true)
    .maybeSingle();
  if (lookupError) redirect("/goals?error=goal-save");

  const result = existing
    ? await supabase.from("goals").update({ target }).eq("id", existing.id).eq("user_id", authData.user.id)
    : await supabase.from("goals").insert({
        user_id: authData.user.id,
        metric,
        target,
        unit: definition.unit,
        cadence: definition.cadence,
      });
  if (result.error) redirect("/goals?error=goal-save");

  revalidatePath("/goals");
  revalidatePath("/dashboard");
  redirect("/goals?saved=goal");
}

export async function archiveGoal(formData: FormData) {
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getUser();
  if (!authData.user) redirect("/auth/sign-in?error=authentication-required");

  const goalID = stringValue(formData.get("goal_id"));
  if (!goalID || !/^[0-9a-f-]{36}$/i.test(goalID)) redirect("/goals?error=invalid-goal");
  const { error } = await supabase
    .from("goals")
    .update({ active: false, ended_on: new Date().toISOString().slice(0, 10) })
    .eq("id", goalID)
    .eq("user_id", authData.user.id)
    .eq("active", true);
  if (error) redirect("/goals?error=goal-archive");

  revalidatePath("/goals");
  revalidatePath("/dashboard");
  redirect("/goals?saved=archived");
}

function stringValue(value: FormDataEntryValue | null): string {
  return typeof value === "string" ? value.trim() : "";
}

function numberValue(value: FormDataEntryValue | null): number {
  const parsed = Number(stringValue(value));
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

function isValidTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}
