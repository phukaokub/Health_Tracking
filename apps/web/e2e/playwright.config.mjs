import { defineConfig } from "@playwright/test";
import { fileURLToPath } from "node:url";

const webRoot = fileURLToPath(new URL("../", import.meta.url));
const apiRoot = fileURLToPath(new URL("../../../services/api/", import.meta.url));
const webURL = "http://127.0.0.1:3102";
const apiURL = "http://127.0.0.1:8181";
const supabaseURL = required("E2E_SUPABASE_URL");
const publishableKey = required("E2E_SUPABASE_PUBLISHABLE_KEY");
const childEnvironment = Object.fromEntries(
  Object.entries(process.env).filter(([name]) => !name.startsWith("E2E_")),
);

export default defineConfig({
  testDir: ".",
  testMatch: "import-upload.spec.mjs",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: "line",
  outputDir: "../test-results/browser",
  timeout: 60_000,
  expect: { timeout: 20_000 },
  use: {
    baseURL: webURL,
    browserName: "chromium",
    headless: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    viewport: { width: 390, height: 844 },
  },
  webServer: [
    {
      name: "API",
      command: "go run ./cmd/api",
      cwd: apiRoot,
      env: {
        ...childEnvironment,
        PORT: "8181",
        WEB_ORIGIN: webURL,
        SUPABASE_URL: supabaseURL,
        SUPABASE_PUBLISHABLE_KEY: publishableKey,
        SUPABASE_JWT_ISSUER: `${supabaseURL}/auth/v1`,
        SUPABASE_JWT_AUDIENCE: "authenticated",
      },
      url: `${apiURL}/api/v1/health`,
      reuseExistingServer: false,
      timeout: 120_000,
      stdout: "pipe",
      stderr: "pipe",
    },
    {
      name: "Web",
      command: "npm run dev -- --hostname 127.0.0.1 --port 3102",
      cwd: webRoot,
      env: {
        ...childEnvironment,
        NEXT_PUBLIC_APP_URL: webURL,
        NEXT_PUBLIC_API_BASE_URL: apiURL,
        NEXT_PUBLIC_SUPABASE_URL: supabaseURL,
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: publishableKey,
        NEXT_PUBLIC_IMPORT_UPLOAD_ENABLED: "true",
        NEXT_DIST_DIR: ".next-e2e",
      },
      url: `${webURL}/auth/sign-in`,
      reuseExistingServer: false,
      timeout: 120_000,
      stdout: "pipe",
      stderr: "pipe",
    },
  ],
});

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}
