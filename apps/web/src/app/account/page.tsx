import { signOut } from "@/app/auth/actions/auth";

export default function AccountPage() {
  return <main className="min-h-screen bg-slate-950 px-5 py-12 text-white"><section className="mx-auto max-w-2xl rounded-3xl border border-white/10 bg-white/10 p-6"><h1 className="text-3xl font-semibold">Account and privacy</h1><p className="mt-3 text-slate-300">Session-aware account details will appear here after Supabase SSR is connected. All profile rows are scoped to the authenticated user by database RLS.</p><form action={signOut} className="mt-6"><button className="rounded-full border border-white/20 px-5 py-2 text-sm font-medium">Sign out</button></form></section></main>;
}
