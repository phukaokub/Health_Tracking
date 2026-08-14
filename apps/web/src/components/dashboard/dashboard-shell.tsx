import Link from "next/link";
import { Activity, BarChart3, Clock3, Goal, LayoutDashboard } from "lucide-react";

const navigation = [
  { href: "/summary", label: "Summary", icon: Clock3 },
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/reports", label: "Reports", icon: BarChart3 },
  { href: "/goals", label: "Goals", icon: Goal },
];

export function DashboardShell({
  active,
  eyebrow,
  title,
  description,
  children,
}: {
  active: string;
  eyebrow: string;
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <main className="min-h-screen bg-slate-950 px-4 py-5 text-white sm:px-6 lg:px-8">
      <div className="mx-auto max-w-7xl">
        <header className="flex flex-col gap-5 border-b border-white/10 pb-5 sm:flex-row sm:items-center sm:justify-between">
          <Link href="/summary" className="flex items-center gap-3 text-sm font-semibold tracking-tight">
            <span className="grid size-9 place-items-center rounded-xl bg-cyan-300 text-slate-950"><Activity className="size-5" aria-hidden="true" /></span>
            Health Tracking
          </Link>
          <nav aria-label="Wellness navigation" className="flex flex-wrap gap-2 text-sm">
            {navigation.map(({ href, label, icon: Icon }) => (
              <Link
                key={href}
                href={href}
                aria-current={active === href ? "page" : undefined}
                className={`inline-flex items-center gap-2 rounded-full px-3 py-2 transition ${active === href ? "bg-white text-slate-950" : "text-slate-300 hover:bg-white/10 hover:text-white"}`}
              >
                <Icon className="size-4" aria-hidden="true" />
                {label}
              </Link>
            ))}
          </nav>
        </header>
        <div className="py-8 sm:py-10">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-300">{eyebrow}</p>
          <h1 className="mt-3 max-w-3xl text-3xl font-semibold tracking-tight sm:text-5xl">{title}</h1>
          <p className="mt-4 max-w-2xl text-sm leading-6 text-slate-300 sm:text-base">{description}</p>
          <div className="mt-8">{children}</div>
        </div>
      </div>
    </main>
  );
}

export function SafeErrorState({ message = "This report could not load right now. Please try again shortly." }: { message?: string }) {
  return <div className="rounded-3xl border border-amber-200/20 bg-amber-300/10 p-6 text-sm text-amber-100" role="alert">{message}</div>;
}

export function EmptyState({ title, description, href = "/import", linkLabel = "Go to import" }: { title: string; description: string; href?: string; linkLabel?: string }) {
  return (
    <div className="rounded-3xl border border-white/10 bg-white/5 p-8 text-center">
      <h2 className="text-xl font-semibold">{title}</h2>
      <p className="mx-auto mt-3 max-w-lg text-sm leading-6 text-slate-300">{description}</p>
      <Link href={href} className="mt-5 inline-flex rounded-full bg-cyan-300 px-5 py-2.5 text-sm font-semibold text-slate-950 hover:bg-cyan-200">{linkLabel}</Link>
    </div>
  );
}
