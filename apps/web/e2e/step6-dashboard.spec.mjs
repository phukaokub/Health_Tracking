import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";

const supabaseURL = required("E2E_SUPABASE_URL");
const adminKey = required("E2E_SUPABASE_ADMIN_KEY");
const admin = createClient(supabaseURL, adminKey, authOptions());

let owner;

test.beforeAll(async () => {
  const stamp = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  owner = { email: `step6-browser-${stamp}@example.test`, password: `Step6-${stamp}!Aa` };
  const { data, error } = await admin.auth.admin.createUser({
    email: owner.email,
    password: owner.password,
    email_confirm: true,
    user_metadata: { display_name: "Synthetic Step 6 Test" },
  });
  if (error || !data.user) throw error ?? new Error("synthetic user was not created");
  owner.id = data.user.id;
});

test.afterAll(async () => {
  if (owner?.id) await admin.auth.admin.deleteUser(owner.id);
});

test("summary, goals, dashboard, and reports render for an authenticated owner", async ({ page }) => {
  await page.goto("/auth/sign-in");
  await page.getByLabel("Email").fill(owner.email);
  await page.getByLabel("Password").fill(owner.password);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page).toHaveURL(/\/account\?status=welcome$/);

  await page.goto("/summary");
  await expect(page.getByRole("heading", { name: "A clear starting point for your wellness data" })).toBeVisible();
  await expect(page.getByText("No completed import yet")).toBeVisible();
  await page.screenshot({ path: "test-results/browser/step6-summary-safe.png", fullPage: true });

  await page.goto("/goals");
  await page.getByLabel("Target (steps)").fill("8000");
  await page.getByRole("button", { name: "Set goal" }).first().click();
  await expect(page).toHaveURL(/\/goals\?(saved=goal|error=[^&]+)$/);
  await expect(page.getByText("Goal saved.")).toBeVisible();

  await page.goto("/dashboard?range=7");
  await expect(page.getByRole("heading", { name: "Your current wellness picture" })).toBeVisible();
  await expect(page.getByText("There is no normalized data in this window yet.")).toBeVisible();

  await page.goto("/reports?range=28");
  await expect(page.getByRole("heading", { name: "Look closer when you want to" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Sleep" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Activity" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Cardio and recovery" })).toBeVisible();
});

function authOptions() {
  return { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
}

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}
