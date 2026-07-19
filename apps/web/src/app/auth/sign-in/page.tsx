import Link from "next/link";
import { LockKeyhole } from "lucide-react";

import { signInWithGoogle, signInWithPassword } from "@/app/auth/actions/auth";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export default async function SignInPage({ searchParams }: { searchParams: Promise<{ error?: string; status?: string }> }) {
  const params = await searchParams;
  const message = params.error === "supabase-env-missing"
    ? "Supabase environment variables are required before local sign-in can complete."
    : params.error === "invalid-credentials"
      ? "That email address or password is incorrect."
      : params.error === "authentication-required"
        ? "Sign in to view your account."
        : params.error === "auth-callback"
          ? "The sign-in callback could not be completed. Please try again."
          : params.error === "google-sign-in-failed"
            ? "Google sign-in is not available until its local provider credentials are configured."
    : params.status === "signed-out"
      ? "You have been signed out."
    : params.status === "check-email"
      ? "Your local confirmation email is in Mailpit at http://127.0.0.1:54324. Open its confirmation link, then return here to sign in."
      : params.status === "password-reset-email-sent"
        ? "If that address has an account, a password-reset email is available in Mailpit locally."
        : null;

  return (
    <main className="min-h-screen bg-slate-950 px-5 py-12 text-white">
      <section className="mx-auto max-w-md rounded-3xl border border-white/10 bg-white/10 p-6 shadow-2xl backdrop-blur">
        <div className="grid size-12 place-items-center rounded-2xl bg-cyan-300 text-slate-950">
          <LockKeyhole className="size-6" aria-hidden="true" />
        </div>
        <h1 className="mt-6 text-3xl font-semibold tracking-tight">Sign in to Health Tracking</h1>
        <p className="mt-2 text-sm leading-6 text-slate-300">Use your verified email and password. Google sign-in can be enabled in local Supabase with PKCE callbacks.</p>
        {message && params.error ? <p className="mt-4 rounded-2xl bg-cyan-300/10 p-3 text-sm text-red-100">{message}</p> : null}
        <form action={signInWithPassword} className="mt-6 space-y-4">
          <label className="block text-sm font-medium">Email<input name="email" type="email" autoComplete="email" required className="mt-2 w-full rounded-xl border border-white/10 bg-slate-900 px-3 py-2 text-white" /></label>
          <label className="block text-sm font-medium">Password<input name="password" type="password" autoComplete="current-password" required className="mt-2 w-full rounded-xl border border-white/10 bg-slate-900 px-3 py-2 text-white" /></label>
          <button className={cn(buttonVariants({ size: "lg" }), "w-full rounded-full bg-cyan-300 text-slate-950 hover:bg-cyan-200")}>Sign in</button>
        </form>
        <form action={signInWithGoogle} className="mt-3">
          <button className="w-full rounded-full border border-white/20 px-4 py-2 text-sm font-medium text-white hover:bg-white/10">Continue with Google</button>
        </form>
        <p className="mt-4 text-sm text-slate-300"><Link href="/auth/forgot-password" className="text-cyan-200 underline">Forgot your password?</Link></p>
        <p className="mt-5 text-sm text-slate-300">New here? <Link href="/auth/sign-up" className="text-cyan-200 underline">Create an account</Link>.</p>
      </section>
    </main>
  );
}
