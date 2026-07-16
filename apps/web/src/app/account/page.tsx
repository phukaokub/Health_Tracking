import { redirect } from "next/navigation";
import Link from "next/link";

import { signOut } from "@/app/auth/actions/auth";
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

  return <main className="min-h-screen bg-slate-950 px-5 py-12 text-white"><section className="mx-auto max-w-2xl rounded-3xl border border-white/10 bg-white/10 p-6"><h1 className="text-3xl font-semibold">Account and privacy</h1><p className="mt-3 text-slate-300">Signed in as {user.email ?? "your private account"}.</p><dl className="mt-6 grid gap-3 rounded-2xl bg-slate-900/70 p-4 text-sm"><div><dt className="text-slate-400">Display name</dt><dd className="mt-1 text-white">{profile?.display_name || "Not set"}</dd></div><div><dt className="text-slate-400">Timezone</dt><dd className="mt-1 text-white">{profile?.timezone ?? "UTC"}</dd></div></dl><p className="mt-5 text-sm text-slate-300">Your profile is read through an owner-only database policy. This is a non-clinical wellness application.</p><Link className="mt-5 inline-block rounded-full bg-white px-5 py-2 text-sm font-semibold text-slate-950" href="/import">Review a local export</Link><form action={signOut} className="mt-6"><button className="rounded-full border border-white/20 px-5 py-2 text-sm font-medium">Sign out</button></form></section></main>;
}
