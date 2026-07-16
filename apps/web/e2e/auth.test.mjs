import assert from "node:assert/strict";
import test from "node:test";

const webURL = process.env.E2E_WEB_URL ?? "http://127.0.0.1:3000";

test("auth: anonymous users are redirected away from account settings", async () => {
  const response = await fetch(`${webURL}/account`, { redirect: "manual" });
  assert.equal(response.status, 307);
  assert.equal(response.headers.get("location"), "/auth/sign-in?error=authentication-required");
});

test("auth: anonymous users are redirected away from import review", async () => {
  const response = await fetch(`${webURL}/import`, { redirect: "manual" });
  assert.equal(response.status, 307);
  assert.equal(response.headers.get("location"), "/auth/sign-in?error=authentication-required");
});

test("auth: sign-in page exposes email/password and Google OAuth entry points", async () => {
  const response = await fetch(`${webURL}/auth/sign-in`);
  assert.equal(response.status, 200);
  const page = await response.text();
  assert.match(page, /Sign in to Health Tracking/);
  assert.match(page, /Continue with Google/);
});
