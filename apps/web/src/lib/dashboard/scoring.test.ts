import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { calculateWellnessScore } from "./scoring";
import type { Goal, ReportData, ReportDay } from "./types";

const goal = (metric: Goal["metric"], target: number): Goal => ({
  id: metric,
  metric,
  target,
  unit: metric === "sleep_duration" ? "hours" : metric === "steps" ? "steps" : metric === "active_minutes" ? "minutes" : "workouts",
  cadence: metric === "workouts" ? "weekly" : "daily",
  active: true,
  started_on: "2026-01-01",
  ended_on: null,
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-01T00:00:00Z",
});

const day = (date: string, multiplier = 1): ReportDay => ({
  date,
  steps: 7500 * multiplier,
  active_minutes: 22 * multiplier,
  calories: 0,
  distance_metres: 0,
  average_heart_rate: null,
  resting_heart_rate: null,
  sleep_hours: 8 * multiplier,
  sleep_session_count: 1,
  activity_minutes: 22 * multiplier,
  activity_count: 1,
  workout_count: multiplier >= 1 ? 1 : 0,
  workout_minutes: 30,
  workout_distance_metres: 0,
  workout_calories: 0,
  record_count: 4,
});

const report = (days: ReportDay[]): ReportData => ({
  timezone: "UTC",
  start_date: days[0]?.date ?? "2026-01-01",
  end_date: days.at(-1)?.date ?? "2026-01-28",
  available_range: { start_date: days[0]?.date ?? null, end_date: days.at(-1)?.date ?? null },
  days,
  coverage: { steps: true, active_minutes: true, sleep: true, activity: true, workouts: true, heart_rate: false },
  all_time_coverage: { steps: true, active_minutes: true, sleep: true, activity: true, workouts: true, heart_rate: false },
});

describe("calculateWellnessScore", () => {
  it("is deterministic and fully available for a complete fixture", () => {
    const days = Array.from({ length: 28 }, (_, index) => day(`2026-01-${String(index + 1).padStart(2, "0")}`));
    const result = calculateWellnessScore(report(days), [goal("steps", 7500)]);

    assert.equal(result.version, "score-v1");
    assert.equal(result.total, 100);
    assert.equal(result.coverage, 100);
    assert.equal(result.trend.status, "stable");
    assert.deepEqual(calculateWellnessScore(report(days), [goal("steps", 7500)]), result);
  });

  it("reweights missing components instead of treating them as low scores", () => {
    const days = Array.from({ length: 28 }, (_, index) => ({ ...day(`2026-01-${String(index + 1).padStart(2, "0")}`), sleep_hours: 0, sleep_session_count: 0, workout_count: 0 }));
    const complete = report(days);
    const result = calculateWellnessScore({ ...complete, coverage: { ...complete.coverage, sleep: false, workouts: false } }, [goal("steps", 7500)]);

    assert.equal(result.total, 100);
    assert.equal(result.components.find((component) => component.key === "sleep")?.score, null);
    assert.equal(result.components.find((component) => component.key === "recovery_cardio")?.score, null);
    assert.ok(result.suggestions.some((suggestion) => suggestion.key === "sleep-coverage"));
  });

  it("detects a descriptive improving 28-day goal trend", () => {
    const days = Array.from({ length: 28 }, (_, index) => day(`2026-01-${String(index + 1).padStart(2, "0")}`, index < 14 ? 0.4 : 1));
    const result = calculateWellnessScore(report(days), [goal("steps", 7500)]);

    assert.equal(result.trend.status, "improving");
    assert.ok((result.trend.change ?? 0) >= 5);
    assert.match(result.trend.evidence, /not a forecast/);
  });
});
