import { Activity, ArrowRight, HeartPulse, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function Home() {
  return (
    <main className="flex flex-1 items-center justify-center bg-background px-6 py-16">
      <div className="grid w-full max-w-6xl gap-12 lg:grid-cols-[1.2fr_0.8fr] lg:items-center">
        <section className="space-y-8">
          <div className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-3 py-1 text-sm text-muted-foreground">
            <Activity className="size-4 text-primary" aria-hidden="true" />
            Step 0 · local developer baseline
          </div>
          <div className="space-y-5">
            <p className="font-mono text-sm uppercase tracking-[0.25em] text-muted-foreground">
              Personal health, made understandable
            </p>
            <h1 className="max-w-3xl text-5xl font-semibold tracking-tight text-foreground sm:text-6xl">
              Your health data, with context you can act on.
            </h1>
            <p className="max-w-2xl text-lg leading-8 text-muted-foreground">
              A private wellness workspace for importing Huawei Health exports,
              understanding trends, and setting goals without pretending to be
              a medical diagnosis.
            </p>
          </div>
          <div className="flex flex-col gap-3 sm:flex-row">
            <Button size="lg" className="gap-2">
              Explore the plan <ArrowRight className="size-4" aria-hidden="true" />
            </Button>
            <Button size="lg" variant="outline">
              Read the privacy promise
            </Button>
          </div>
        </section>
        <aside className="rounded-3xl border border-border bg-card p-6 shadow-sm">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-muted-foreground">
                Product principles
              </p>
              <h2 className="mt-2 text-2xl font-semibold">Clear, private, explainable</h2>
            </div>
            <HeartPulse className="size-6 text-primary" aria-hidden="true" />
          </div>
          <div className="mt-8 space-y-5">
            <div className="flex gap-3">
              <ShieldCheck className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden="true" />
              <div>
                <p className="font-medium">Private by default</p>
                <p className="mt-1 text-sm leading-6 text-muted-foreground">
                  Raw exports, GPS tracks, and ECG waveforms stay out of the first release.
                </p>
              </div>
            </div>
            <div className="flex gap-3">
              <Activity className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden="true" />
              <div>
                <p className="font-medium">One verified step at a time</p>
                <p className="mt-1 text-sm leading-6 text-muted-foreground">
                  Every milestone has a local test gate before cloud deployment.
                </p>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </main>
  );
}

