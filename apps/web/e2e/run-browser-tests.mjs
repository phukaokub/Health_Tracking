import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const webRoot = fileURLToPath(new URL("../", import.meta.url));
const repositoryRoot = fileURLToPath(new URL("../../../", import.meta.url));
const npx = process.platform === "win32" ? "npx.cmd" : "npx";

const status = runNpx(["--yes", "supabase@2.109.1", "status", "--output", "env"], {
  cwd: repositoryRoot,
  encoding: "utf8",
  windowsHide: true,
});
if (status.status !== 0) {
  console.error("Local Supabase is unavailable. Start it with `npx supabase start` and retry.");
  process.exit(status.status ?? 1);
}

const local = Object.fromEntries(
  status.stdout
    .split(/\r?\n/)
    .map((line) => line.match(/^([A-Z0-9_]+)="(.*)"$/))
    .filter(Boolean)
    .map((match) => [match[1], match[2]]),
);
for (const name of ["API_URL", "PUBLISHABLE_KEY"]) {
  if (!local[name]) {
    console.error(`Local Supabase status did not provide ${name}.`);
    process.exit(1);
  }
}
const adminKey = local.SECRET_KEY || local.SERVICE_ROLE_KEY;
if (!adminKey) {
  console.error("Local Supabase status did not provide a server-only test administration key.");
  process.exit(1);
}

const result = runNpx(["playwright", "test", "--config", "e2e/playwright.config.mjs"], {
  cwd: webRoot,
  env: {
    ...process.env,
    E2E_SUPABASE_URL: local.API_URL,
    E2E_SUPABASE_PUBLISHABLE_KEY: local.PUBLISHABLE_KEY,
    E2E_SUPABASE_ADMIN_KEY: adminKey,
  },
  stdio: "inherit",
  windowsHide: true,
});
process.exitCode = result.status ?? 1;

function runNpx(args, options) {
  if (process.platform === "win32") {
    return spawnSync(`${npx} ${args.join(" ")}`, { ...options, shell: true });
  }
  return spawnSync(npx, args, options);
}
