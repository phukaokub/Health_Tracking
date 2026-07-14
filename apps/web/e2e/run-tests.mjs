import { spawnSync } from "node:child_process";

const suite = process.argv[2] ?? "auth";
const testFile = suite === "auth" ? "e2e/auth.test.mjs" : null;

if (!testFile) {
  console.error(`Unknown E2E suite: ${suite}`);
  process.exitCode = 1;
} else {
  const result = spawnSync(process.execPath, ["--test", testFile], { stdio: "inherit" });
  process.exitCode = result.status ?? 1;
}
