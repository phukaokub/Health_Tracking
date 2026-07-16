import { createSHA256, type IHasher } from "hash-wasm";

import type { ScannedPart } from "./scanner.types";

export const MAX_LOGICAL_PART_BYTES = 20 * 1024 * 1024;

export class StreamingHashes {
  private partBytes = 0;
  private partOffset = 0;
  private parts: ScannedPart[] = [];

  private constructor(
    private readonly contentHasher: IHasher,
    private readonly partHasher: IHasher,
    private readonly partSize: number,
  ) {}

  static async create(partSize = MAX_LOGICAL_PART_BYTES): Promise<StreamingHashes> {
    if (!Number.isSafeInteger(partSize) || partSize < 1) throw new Error("invalid_part_size");
    return new StreamingHashes(await createSHA256(), await createSHA256(), partSize);
  }

  reset(): void {
    this.contentHasher.init();
    this.partHasher.init();
    this.partBytes = 0;
    this.partOffset = 0;
    this.parts = [];
  }

  update(value: Uint8Array): void {
    this.contentHasher.update(value);
    let chunkOffset = 0;
    while (chunkOffset < value.byteLength) {
      const length = Math.min(this.partSize - this.partBytes, value.byteLength - chunkOffset);
      this.partHasher.update(value.subarray(chunkOffset, chunkOffset + length));
      this.partBytes += length;
      chunkOffset += length;
      if (this.partBytes === this.partSize) this.finishPart();
    }
  }

  digest(): { contentSha256: string; parts: ScannedPart[] } {
    if (this.partBytes > 0) this.finishPart();
    return { contentSha256: this.contentHasher.digest("hex"), parts: [...this.parts] };
  }

  private finishPart(): void {
    this.parts.push({
      partIndex: this.parts.length,
      byteOffset: this.partOffset,
      byteLength: this.partBytes,
      contentSha256: this.partHasher.digest("hex"),
    });
    this.partOffset += this.partBytes;
    this.partBytes = 0;
    this.partHasher.init();
  }
}
