import assert from "node:assert/strict";
import test from "node:test";

import { strToU8, Unzip, UnzipInflate, zipSync } from "fflate";

test("fflate streams ZIP entries supplied in bounded chunks", () => {
  const archive = zipSync({ "export/records.json": strToU8('{"synthetic":true}') });
  const unzipped: Record<string, Uint8Array> = {};
  const unzip = new Unzip();
  unzip.register(UnzipInflate);
  unzip.onfile = (file) => {
    const chunks: Uint8Array[] = [];
    file.ondata = (error, chunk, final) => {
      assert.equal(error, null);
      if (chunk) chunks.push(chunk);
      if (final) unzipped[file.name] = Uint8Array.from(chunks.flatMap((value) => [...value]));
    };
    file.start();
  };

  const halfway = Math.ceil(archive.length / 2);
  unzip.push(archive.subarray(0, halfway), false);
  unzip.push(archive.subarray(halfway), true);

  assert.deepEqual(unzipped["export/records.json"], strToU8('{"synthetic":true}'));
});
