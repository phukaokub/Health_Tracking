import Link from "next/link";

import { requestPasswordReset } from "@/app/auth/actions/auth";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export default async function ForgotPasswordPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  const message = error === "missing-email"
    ? "Enter the email address for your account."
    : error === "password-reset-failed"
      ? "The password reset request could not be started. Please try again."
      : null;

  return <main className="min-h-screen bg-slate-950 px-5 py-12 text-white"><section className="mx-auto max-w-md rounded-3xl border border-white/10 bg-white/10 p-6"><h1 className="text-3xl font-semibold">Reset your password</h1><p className="mt-2 text-sm leading-6 text-slate-300">We will send a recovery link for a password-enabled account. Local messages appear in Mailpit.</p>{message ? <p className="mt-4 rounded-2xl bg-red-400/10 p-3 text-sm text-red-100">{message}</p> : null}<form action={requestPasswordReset} className="mt-6 space-y-4"><label className="block text-sm font-medium">Email<input name="email" type="email" autoComplete="email" required className="mt-2 w-full rounded-xl border border-white/10 bg-slate-900 px-3 py-2 text-white" /></label><button className={cn(buttonVariants({ size: "lg" }), "w-full rounded-full bg-cyan-300 text-slate-950 hover:bg-cyan-200")}>Send recovery link</button></form><p className="mt-5 text-sm text-slate-300"><Link href="/auth/sign-in" className="text-cyan-200 underline">Back to sign in</Link></p></section></main>;
}
