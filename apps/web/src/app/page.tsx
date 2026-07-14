import Image from "next/image";
import Link from "next/link";
import {
  ArrowRight,
  Check,
  ChevronDown,
  HeartPulse,
  LockKeyhole,
  Menu,
  Sparkles,
} from "lucide-react";

import { ReportPreview } from "@/components/landing/report-preview";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const trustPoints = [
  "Import Huawei Health exports",
  "See your sleep, activity, and recovery together",
  "Private by default — wellness, not diagnosis",
];

export default function Home() {
  return (
    <main className="min-h-screen bg-slate-950 text-white">
      <section className="relative isolate min-h-screen overflow-hidden">
        <Image
          src="/images/hero-runner.png"
          alt=""
          fill
          priority
          sizes="100vw"
          className="object-cover object-[68%_center]"
        />
        <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(2,8,23,0.97)_0%,rgba(2,8,23,0.91)_36%,rgba(2,8,23,0.49)_66%,rgba(2,8,23,0.22)_100%)]" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_14%_8%,rgba(45,212,191,0.19),transparent_36%),radial-gradient(circle_at_75%_80%,rgba(251,146,60,0.19),transparent_32%)]" />

        <div className="relative mx-auto flex min-h-screen max-w-7xl flex-col px-5 sm:px-8 lg:px-10">
          <nav className="flex items-center justify-between py-6 sm:py-8" aria-label="Main navigation">
            <Link href="/" className="flex items-center gap-2 text-base font-semibold tracking-tight">
              <span className="grid size-9 place-items-center rounded-xl bg-white text-slate-950 shadow-lg shadow-sky-950/30">
                <HeartPulse className="size-5" aria-hidden="true" />
              </span>
              Health Tracking
            </Link>

            <div className="hidden items-center gap-7 text-sm text-slate-200 md:flex">
              <Link href="#how-it-works" className="transition hover:text-white">How it works</Link>
              <Link href="#sample-report" className="transition hover:text-white">Sample report</Link>
              <Link href="#privacy" className="transition hover:text-white">Privacy</Link>
              <Link href="#signin" className="transition hover:text-white">Sign in</Link>
              <Link
                href="#start"
                className={cn(buttonVariants({ size: "lg" }), "h-10 rounded-full bg-white px-5 text-slate-950 hover:bg-slate-100")}
              >
                Get started
              </Link>
            </div>

            <button
              className="grid size-10 place-items-center rounded-full border border-white/20 bg-white/10 md:hidden"
              aria-label="Open navigation menu"
            >
              <Menu className="size-5" aria-hidden="true" />
            </button>
          </nav>

          <div className="grid flex-1 items-center gap-10 pb-14 pt-7 lg:grid-cols-[0.83fr_1.17fr] lg:gap-6 lg:pb-20">
            <div className="max-w-xl py-8 lg:py-16">
              <div className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/10 px-3 py-1.5 text-xs font-medium text-sky-100 backdrop-blur-sm">
                <Sparkles className="size-3.5 text-cyan-300" aria-hidden="true" />
                Built for your Huawei Health export
              </div>

              <p className="mt-8 text-xs font-semibold uppercase tracking-[0.22em] text-cyan-200">
                Personal wellness, made clear
              </p>
              <h1 className="mt-4 text-5xl font-semibold tracking-[-0.055em] text-white sm:text-6xl lg:text-7xl">
                Your health data, <span className="text-cyan-200">in focus.</span>
              </h1>
              <p className="mt-6 max-w-lg text-base leading-7 text-slate-200 sm:text-lg">
                Turn sleep, activity, heart rate, and recovery data into a calm, useful picture of your week — then set goals that fit your life.
              </p>

              <div id="start" className="mt-8 flex flex-col gap-3 sm:flex-row">
                <Link
                  href="#how-it-works"
                  className={cn(buttonVariants({ size: "lg" }), "h-12 rounded-full bg-cyan-300 px-6 text-slate-950 hover:bg-cyan-200")}
                >
                  Start with your export <ArrowRight className="size-4" aria-hidden="true" />
                </Link>
                <Link
                  href="#sample-report"
                  className={cn(buttonVariants({ variant: "outline", size: "lg" }), "h-12 rounded-full border-white/25 bg-white/5 px-6 text-white hover:bg-white/15 hover:text-white")}
                >
                  View sample report
                </Link>
              </div>

              <ul className="mt-9 space-y-3 text-sm text-slate-200">
                {trustPoints.map((point) => (
                  <li key={point} className="flex items-center gap-3">
                    <span className="grid size-5 place-items-center rounded-full bg-emerald-300/15 text-emerald-200">
                      <Check className="size-3.5" aria-hidden="true" />
                    </span>
                    {point}
                  </li>
                ))}
              </ul>
            </div>

            <div className="relative mx-auto w-full max-w-2xl pb-8 pt-4 lg:translate-x-8 lg:pb-0">
              <div className="absolute -inset-10 rounded-full bg-cyan-400/20 blur-3xl" />
              <div className="relative">
                <ReportPreview />
                <div className="absolute -bottom-5 -left-3 hidden items-center gap-3 rounded-2xl border border-white/25 bg-slate-950/85 px-4 py-3 text-sm shadow-xl backdrop-blur-md sm:flex">
                  <span className="grid size-8 place-items-center rounded-xl bg-teal-300 text-slate-950">
                    <LockKeyhole className="size-4" aria-hidden="true" />
                  </span>
                  <span>
                    <span className="block text-xs text-slate-300">Your data stays yours</span>
                    <span className="font-medium">Private by default</span>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div id="how-it-works" className="flex items-center gap-2 pb-6 text-xs text-slate-300">
            <ChevronDown className="size-4 text-cyan-200" aria-hidden="true" />
            Import → understand → improve
          </div>
        </div>
      </section>

      <section id="privacy" className="border-t border-slate-800 bg-slate-950 px-5 py-12 sm:px-8 lg:px-10">
        <div className="mx-auto flex max-w-7xl flex-col gap-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-cyan-300">Designed for perspective</p>
            <h2 className="mt-2 text-2xl font-semibold tracking-tight">Health reports that feel like yours.</h2>
          </div>
          <p className="max-w-md text-sm leading-6 text-slate-400">
            The preview uses illustrative sample data. The app is a wellness tool, not a medical device or diagnostic service.
          </p>
        </div>
      </section>
    </main>
  );
}
