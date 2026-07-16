"use server";

import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

function appUrl() {
  return process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
}

export async function signInWithPassword(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) redirect("/auth/sign-in?error=missing-credentials");

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) redirect("/auth/sign-in?error=invalid-credentials");

  redirect("/account?status=welcome");
}

export async function signUpWithPassword(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const displayName = String(formData.get("displayName") ?? "").trim();
  if (!email || !password || password.length < 8) redirect("/auth/sign-up?error=invalid-credentials");

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { display_name: displayName } },
  });
  if (error) redirect("/auth/sign-up?error=sign-up-failed");
  if (!data.session) redirect("/auth/sign-in?status=check-email");

  redirect("/account?status=welcome");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/auth/sign-in?status=signed-out");
}

export async function signInWithGoogle() {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: `${appUrl()}/auth/callback` },
  });

  if (error || !data.url) redirect("/auth/sign-in?error=google-sign-in-failed");
  redirect(data.url);
}

export async function requestPasswordReset(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  if (!email) redirect("/auth/forgot-password?error=missing-email");

  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${appUrl()}/auth/callback?next=/auth/reset-password`,
  });
  if (error) redirect("/auth/forgot-password?error=password-reset-failed");

  redirect("/auth/sign-in?status=password-reset-email-sent");
}

export async function updatePassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("confirmation") ?? "");
  if (password.length < 8 || password !== confirmation) {
    redirect("/auth/reset-password?error=invalid-password");
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect("/auth/reset-password?error=password-update-failed");

  redirect("/account?status=password-updated");
}
