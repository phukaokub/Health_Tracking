import { redirect } from "next/navigation";
import Link from "next/link";

import { signOut } from "@/app/auth/actions/auth";
import { AppShell } from "@/components/summary/summary-ui";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function AccountPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/sign-in?error=authentication-required");

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name, timezone")
    .eq("id", user.id)
    .maybeSingle();

  return (
    <AppShell active="account">
      <div className="mx-auto max-w-4xl px-5 py-10 text-white sm:px-8 sm:py-16">
        <div className="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
          <section className="rounded-3xl border border-white/10 bg-white/10 p-6 sm:p-8">
            <p className="text-xs font-semibold uppercase tracking-[0.22em] text-cyan-300">Profile</p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight">Account and privacy</h1>
            <p className="mt-3 text-slate-300">Signed in as {user.email ?? "your private account"}.</p>
            <dl className="mt-6 grid gap-3 rounded-2xl bg-slate-900/70 p-4 text-sm sm:grid-cols-2">
              <div><dt className="text-slate-400">Display name</dt><dd className="mt-1 text-white">{profile?.display_name || "Not set"}</dd></div>
              <div><dt className="text-slate-400">Timezone</dt><dd className="mt-1 text-white">{profile?.timezone ?? "UTC"}</dd></div>
            </dl>
            <p className="mt-5 text-sm leading-6 text-slate-300">Your profile is read through an owner-only database policy. This is a non-clinical wellness application.</p>
            <div className="mt-7 flex flex-wrap gap-3">
              <Link className="rounded-full bg-cyan-300 px-5 py-2.5 text-sm font-semibold text-slate-950 hover:bg-cyan-200" href="/import">Import health data</Link>
              <Link className="rounded-full border border-white/20 px-5 py-2.5 text-sm font-medium text-white hover:bg-white/10" href="/dashboard">Back to dashboard</Link>
            </div>
          </section>
          <aside className="rounded-3xl border border-white/10 bg-slate-900/70 p-6 sm:p-8">
            <p className="text-sm font-semibold text-white">Your next step</p>
            <p className="mt-2 text-sm leading-6 text-slate-400">Import a new export from your device, then follow its processing status from the import page.</p>
            <Link href="/import" className="mt-5 inline-flex rounded-full border border-cyan-300/40 px-4 py-2 text-sm font-medium text-cyan-100 hover:bg-cyan-300/10">Open import</Link>
            <form action={signOut} className="mt-10"><button className="rounded-full border border-white/20 px-5 py-2 text-sm font-medium text-slate-200 hover:bg-white/10">Sign out</button></form>
          </aside>
        </div>
      </div>
    </AppShell>
  );
}
