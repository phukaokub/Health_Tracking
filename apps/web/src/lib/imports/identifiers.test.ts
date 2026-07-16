import assert from "node:assert/strict";
import test from "node:test";

import { sha256Text, uuidFromSHA256 } from "./identifiers";

test("privacy-safe hashes produce stable RFC variant UUID identifiers", async () => {
  const hash = await sha256Text("synthetic/export/records.json");
  const first = uuidFromSHA256(hash);
  const second = uuidFromSHA256(hash);

  assert.equal(first, second);
  assert.match(first, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});
