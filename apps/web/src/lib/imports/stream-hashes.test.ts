import assert from "node:assert/strict";
import test from "node:test";

import { StreamingHashes } from "./stream-hashes";

test("streaming hashes split exact logical boundaries without losing bytes", async () => {
  const hashes = await StreamingHashes.create(4);
  hashes.update(Uint8Array.from([0, 1, 2]));
  hashes.update(Uint8Array.from([3, 4, 5, 6, 7, 8]));
  const result = hashes.digest();

  assert.deepEqual(result.parts.map(({ byteOffset, byteLength, partIndex }) => ({ byteOffset, byteLength, partIndex })), [
    { partIndex: 0, byteOffset: 0, byteLength: 4 },
    { partIndex: 1, byteOffset: 4, byteLength: 4 },
    { partIndex: 2, byteOffset: 8, byteLength: 1 },
  ]);
  assert.match(result.contentSha256, /^[0-9a-f]{64}$/);
  assert.ok(result.parts.every((part) => /^[0-9a-f]{64}$/.test(part.contentSha256)));
});

test("streaming hashes reset without retaining prior export metadata", async () => {
  const hashes = await StreamingHashes.create(4);
  hashes.update(Uint8Array.from([1, 2, 3]));
  const first = hashes.digest();
  hashes.reset();
  hashes.update(Uint8Array.from([4]));
  const second = hashes.digest();

  assert.equal(first.parts[0]?.byteLength, 3);
  assert.equal(second.parts[0]?.byteLength, 1);
  assert.notEqual(first.contentSha256, second.contentSha256);
});
