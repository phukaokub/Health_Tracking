import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { zipSync } from "fflate";

const supabaseURL = required("E2E_SUPABASE_URL");
const publishableKey = required("E2E_SUPABASE_PUBLISHABLE_KEY");
const adminKey = required("E2E_SUPABASE_ADMIN_KEY");
const apiURL = "http://127.0.0.1:8181";
const admin = createClient(supabaseURL, adminKey, authOptions());

test.describe.configure({ mode: "serial" });

let owner;
let other;
let ownerToken;
let otherToken;
let ownerData;
const createdImportIDs = new Set();

test.beforeAll(async () => {
  const stamp = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  owner = await createUser(`step3-owner-${stamp}@example.test`, `Step3-Owner-${stamp}!Aa`);
  other = await createUser(`step3-other-${stamp}@example.test`, `Step3-Other-${stamp}!Aa`);
  ownerToken = await signIn(owner.email, owner.password);
  otherToken = await signIn(other.email, other.password);
  ownerData = dataClient(ownerToken);
});

test.afterAll(async () => {
  const { data: remainingRuns } = ownerData
    ? await ownerData.from("import_runs").select("id").neq("state", "deleted")
    : { data: [] };
  for (const run of remainingRuns ?? []) createdImportIDs.add(run.id);
  for (const importID of createdImportIDs) {
    await fetch(`${apiURL}/api/v1/imports/${importID}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${ownerToken}` },
    }).catch(() => undefined);
  }
  if (owner?.id) await admin.auth.admin.deleteUser(owner.id);
  if (other?.id) await admin.auth.admin.deleteUser(other.id);
});

test("ZIP upload pauses, survives refresh and queues exactly one owner-scoped job", async ({ page }) => {
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  await signInThroughUI(page, owner);
  await page.getByRole("link", { name: "Review a local export" }).click();
  await expect(page.getByRole("heading", { name: "Review and import a health export" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Choose export folder" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Choose ZIP export" })).toBeVisible();
  await page.getByRole("button", { name: "Choose export folder" }).focus();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("button", { name: "Choose ZIP export" })).toBeFocused();

  const archive = syntheticZIP(8 * 1024 * 1024, 17);
  await selectZIP(page, archive);
  await expect(page.getByText(/1 supported files/)).toBeVisible();

  const pauseGate = await blockFirstTUSPatch(page);
  await page.getByRole("button", { name: "Upload supported files" }).click();
  await pauseGate.started;
  await expect(page.locator('[aria-live="polite"]')).toContainText("Uploading directly to private Storage");
  await page.getByRole("button", { name: "Pause" }).click();
  pauseGate.release();
  await expect(page.locator('[aria-live="polite"]')).toContainText("Upload paused");

  await page.reload();
  await selectZIP(page, archive);
  await expect(page.getByText(/1 supported files/)).toBeVisible();
  await page.getByRole("button", { name: "Upload supported files" }).click();
  await expect(page.getByText("Upload verified and queued. Parsing begins in Step 4.")).toBeVisible({ timeout: 40_000 });

  const run = await latestRun();
  createdImportIDs.add(run.id);
  expect(run.state).toBe("queued");
  const { count: jobCount, error: jobError } = await ownerData
    .from("import_jobs")
    .select("id", { count: "exact", head: true })
    .eq("import_id", run.id);
  expect(jobError).toBeNull();
  expect(jobCount).toBe(1);

  const denied = await fetch(`${apiURL}/api/v1/imports/${run.id}`, {
    headers: { Authorization: `Bearer ${otherToken}` },
  });
  expect(denied.status).toBe(404);

  const deleted = await deleteImport(run.id, ownerToken);
  expect(deleted.state).toBe("deleted");
  createdImportIDs.delete(run.id);
  await expectImportStorageEmpty(owner.id, run.id);
  expect(pageErrors).toEqual([]);
});

test("cancelling an active ZIP upload deletes caller-owned objects and metadata", async ({ page }) => {
  await signInThroughUI(page, owner);
  await page.getByRole("link", { name: "Review a local export" }).click();
  const archive = syntheticZIP(8 * 1024 * 1024, 29);
  await selectZIP(page, archive);
  await expect(page.getByText(/1 supported files/)).toBeVisible();

  const cancelGate = await blockFirstTUSPatch(page);
  await page.getByRole("button", { name: "Upload supported files" }).click();
  await cancelGate.started;
  await page.getByRole("button", { name: "Cancel and delete" }).click();
  cancelGate.release();
  await expect(page.getByText("Import cancelled and uploaded objects deleted.")).toBeVisible();

  const run = await latestRun();
  expect(run.state).toBe("deleted");
  await expectImportStorageEmpty(owner.id, run.id);
});

async function signInThroughUI(page, user) {
  await page.goto("/auth/sign-in");
  await page.getByLabel("Email").fill(user.email);
  await page.getByLabel("Password").fill(user.password);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page).toHaveURL(/\/account\?status=welcome$/);
  await expect(page.getByText("Account and privacy")).toBeVisible();
}

async function selectZIP(page, archive) {
  await page.locator('input[accept*=".zip"]').setInputFiles({
    name: "synthetic-health-export.zip",
    mimeType: "application/zip",
    buffer: Buffer.from(archive),
  });
}

async function blockFirstTUSPatch(page) {
  let startedResolve;
  let releaseResolve;
  let blocked = false;
  const started = new Promise((resolve) => { startedResolve = resolve; });
  const released = new Promise((resolve) => { releaseResolve = resolve; });
  await page.route(`${supabaseURL}/storage/v1/upload/resumable**`, async (route) => {
    if (!blocked && route.request().method() === "PATCH") {
      blocked = true;
      startedResolve();
      await released;
    }
    await route.continue().catch(() => undefined);
  });
  return { started, release: () => releaseResolve() };
}

function syntheticZIP(bytes, seed) {
  const content = new Uint8Array(bytes);
  let value = seed;
  for (let index = 0; index < content.length; index += 1) {
    value = (value * 1664525 + 1013904223) >>> 0;
    content[index] = value & 0xff;
  }
  return zipSync({ "export/records.json": content }, { level: 0 });
}

async function createUser(email, password) {
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: "Synthetic Step 3 Test" },
  });
  if (error || !data.user) throw error ?? new Error("test user was not created");
  return { id: data.user.id, email, password };
}

async function signIn(email, password) {
  const client = createClient(supabaseURL, publishableKey, authOptions());
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error || !data.session) throw error ?? new Error("test user did not receive a session");
  return data.session.access_token;
}

async function latestRun() {
  const { data, error } = await ownerData
    .from("import_runs")
    .select("id,state,created_at")
    .order("created_at", { ascending: false })
    .limit(1)
    .single();
  if (error) throw error;
  return data;
}

async function deleteImport(importID, token) {
  const response = await fetch(`${apiURL}/api/v1/imports/${importID}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
  expect(response.status).toBe(200);
  return response.json();
}

async function expectImportStorageEmpty(userID, importID) {
  const { data, error } = await ownerData.storage
    .from("health-imports")
    .list(`imports/${userID}/${importID}`, { limit: 100 });
  expect(error).toBeNull();
  expect(data).toEqual([]);
}

function authOptions() {
  return { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
}

function dataClient(token) {
  return createClient(supabaseURL, publishableKey, {
    ...authOptions(),
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}
