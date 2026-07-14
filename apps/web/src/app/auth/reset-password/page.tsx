import { updatePassword } from "@/app/auth/actions/auth";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export default async function ResetPasswordPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  const message = error === "invalid-password"
    ? "Use matching passwords with at least 8 characters."
    : error === "password-update-failed"
      ? "This recovery link is invalid or expired. Request a new one."
      : null;

  return <main className="min-h-screen bg-slate-950 px-5 py-12 text-white"><section className="mx-auto max-w-md rounded-3xl border border-white/10 bg-white/10 p-6"><h1 className="text-3xl font-semibold">Choose a new password</h1>{message ? <p className="mt-4 rounded-2xl bg-red-400/10 p-3 text-sm text-red-100">{message}</p> : null}<form action={updatePassword} className="mt-6 space-y-4"><label className="block text-sm font-medium">New password<input name="password" type="password" autoComplete="new-password" minLength={8} required className="mt-2 w-full rounded-xl border border-white/10 bg-slate-900 px-3 py-2 text-white" /></label><label className="block text-sm font-medium">Confirm password<input name="confirmation" type="password" autoComplete="new-password" minLength={8} required className="mt-2 w-full rounded-xl border border-white/10 bg-slate-900 px-3 py-2 text-white" /></label><button className={cn(buttonVariants({ size: "lg" }), "w-full rounded-full bg-cyan-300 text-slate-950 hover:bg-cyan-200")}>Save password</button></form></section></main>;
}
