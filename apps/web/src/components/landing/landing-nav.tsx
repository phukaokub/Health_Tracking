"use client";

import Link from "next/link";
import { HeartPulse, Menu, X } from "lucide-react";
import { useState } from "react";

import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const links = [
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#sample-report", label: "Sample report" },
  { href: "/#privacy", label: "Privacy" },
  { href: "/auth/sign-in", label: "Sign in" },
];

export function LandingNav() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <nav className="relative flex items-center justify-between py-6 sm:py-8" aria-label="Main navigation">
      <Link href="/" className="flex items-center gap-2 text-base font-semibold tracking-tight" onClick={() => setIsOpen(false)}>
        <span className="grid size-9 place-items-center rounded-xl bg-white text-slate-950 shadow-lg shadow-sky-950/30">
          <HeartPulse className="size-5" aria-hidden="true" />
        </span>
        Health Tracking
      </Link>

      <div className="hidden items-center gap-7 text-sm text-slate-200 md:flex">
        {links.map((link) => (
          <Link key={link.href} href={link.href} className="transition hover:text-white">
            {link.label}
          </Link>
        ))}
        <Link href="/auth/sign-in" className={cn(buttonVariants({ size: "lg" }), "h-10 rounded-full bg-white px-5 text-slate-950 hover:bg-slate-100")}>
          Get started
        </Link>
      </div>

      <button
        type="button"
        className="grid size-10 place-items-center rounded-full border border-white/20 bg-white/10 md:hidden"
        aria-label={isOpen ? "Close navigation menu" : "Open navigation menu"}
        aria-expanded={isOpen}
        aria-controls="mobile-navigation"
        onClick={() => setIsOpen((open) => !open)}
      >
        {isOpen ? <X className="size-5" aria-hidden="true" /> : <Menu className="size-5" aria-hidden="true" />}
      </button>

      {isOpen ? (
        <div id="mobile-navigation" className="absolute inset-x-0 top-full z-20 rounded-2xl border border-white/15 bg-slate-950/95 p-3 shadow-2xl backdrop-blur md:hidden">
          <div className="grid gap-1 text-sm text-slate-200">
            {links.map((link) => (
              <Link key={link.href} href={link.href} className="rounded-xl px-4 py-3 hover:bg-white/10 hover:text-white" onClick={() => setIsOpen(false)}>
                {link.label}
              </Link>
            ))}
            <Link href="/auth/sign-in" className={cn(buttonVariants({ size: "lg" }), "mt-1 rounded-xl bg-cyan-300 text-slate-950 hover:bg-cyan-200")} onClick={() => setIsOpen(false)}>
              Get started
            </Link>
          </div>
        </div>
      ) : null}
    </nav>
  );
}
