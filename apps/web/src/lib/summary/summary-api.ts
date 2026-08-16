import { createClient } from "@/lib/supabase/server";

export type SummaryWindow = 7 | 28 | 90;

export type SummarySnapshot = {
  window_days: SummaryWindow;
  timezone: string;
  coverage: {
    first_day: string | null;
    last_day: string | null;
    days_with_data: number;
    window_start: string;
    window_end: string;
  };
  quality: {
    import_state: string;
    import_timezone: string | null;
    verified_file_count: number;
    skipped_duplicate_file_count: number;
    normalized_record_count: number;
    warning_codes: string[];
    source_families: string[];
  };
  metrics: Array<{
    day: string;
    steps: number;
    active_minutes: number;
    sleep_minutes: number;
    workouts: number;
    heart_rate_samples: number;
    data_available: boolean;
  }>;
};

export class SummaryAPIError extends Error {
  constructor(public readonly code: string, public readonly status = 500) {
    super(code);
  }
}

export async function getSummary(windowDays: SummaryWindow): Promise<SummarySnapshot> {
  const baseURL = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (!baseURL) throw new SummaryAPIError("api_not_configured", 503);

  const supabase = await createClient();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) throw new SummaryAPIError("authentication_required", 401);

  const response = await fetch(
    `${baseURL.replace(/\/$/, "")}/api/v1/summary?window=${windowDays}`,
    {
      cache: "no-store",
      headers: { Authorization: `Bearer ${session.access_token}` },
    },
  );
  const payload = await response.json().catch(() => ({})) as { error?: string };
  if (!response.ok) throw new SummaryAPIError(payload.error ?? "summary_unavailable", response.status);
  return payload as SummarySnapshot;
}
