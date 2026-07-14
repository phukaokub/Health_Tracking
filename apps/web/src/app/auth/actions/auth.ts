"use server";

import { redirect } from "next/navigation";

function requireSupabaseEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    redirect("/auth/sign-in?error=supabase-env-missing");
  }

  return { url, anonKey };
}

export async function signInWithPassword(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) {
    redirect("/auth/sign-in?error=missing-credentials");
  }

  requireSupabaseEnv();
  redirect("/account?status=configure-supabase-ssr");
}

export async function signUpWithPassword(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const displayName = String(formData.get("displayName") ?? "").trim();

  if (!email || !password || password.length < 8) {
    redirect("/auth/sign-up?error=invalid-credentials");
  }

  void displayName;
  requireSupabaseEnv();
  redirect("/auth/sign-in?status=check-email");
}

export async function signOut() {
  redirect("/auth/sign-in?status=signed-out");
}
