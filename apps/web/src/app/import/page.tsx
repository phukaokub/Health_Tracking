import { redirect } from "next/navigation";
import Link from "next/link";

import { ImportScanner } from "@/components/imports/import-scanner";
import { AppShell } from "@/components/summary/summary-ui";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ImportPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/sign-in?error=authentication-required");

  return (
    <AppShell active="import">
      <div className="mx-auto max-w-4xl px-5 py-10 text-white sm:px-8 sm:py-16">
        <div className="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-white/10 bg-slate-900/70 px-4 py-3 text-sm">
          <div>
            <p className="font-medium text-white">Import center</p>
            <p className="mt-1 text-slate-400">Review locally, upload privately, and follow processing here.</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Link href="/dashboard" className="rounded-full border border-white/20 px-4 py-2 text-slate-200 hover:bg-white/10">Back to dashboard</Link>
            <Link href="/account" className="rounded-full border border-cyan-300/40 px-4 py-2 text-cyan-100 hover:bg-cyan-300/10">Profile</Link>
          </div>
        </div>
        <ImportScanner />
      </div>
    </AppShell>
  );
}
