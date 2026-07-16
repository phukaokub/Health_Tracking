import type { DirectoryScanInput, DirectoryScanResult, ScanProgress } from "./scanner.types";

type PendingScan = {
  reject: (reason: Error) => void;
  resolve: (result: DirectoryScanResult) => void;
};

export class DirectoryScanner {
  private readonly worker = new Worker(new URL("./scanner.worker.ts", import.meta.url));
  private pending = new Map<string, PendingScan>();

  constructor() {
    this.worker.onmessage = (event: MessageEvent<
      | { id: string; type: "progress"; progress: ScanProgress }
      | { id: string; type: "completed"; result: DirectoryScanResult }
      | { id: string; type: "cancelled" }
      | { id: string; type: "failed"; code: "scan_failed" }
    >) => {
      const pending = this.pending.get(event.data.id);
      if (!pending) return;
      if (event.data.type === "completed") {
        this.pending.delete(event.data.id);
        pending.resolve(event.data.result);
      }
      if (event.data.type === "cancelled") {
        this.pending.delete(event.data.id);
        pending.reject(new Error("scan_cancelled"));
      }
      if (event.data.type === "failed") {
        this.pending.delete(event.data.id);
        pending.reject(new Error(event.data.code));
      }
    };
  }

  scan(files: DirectoryScanInput[], onProgress?: (progress: ScanProgress) => void): Promise<DirectoryScanResult> {
    const id = crypto.randomUUID();
    const listener = (event: MessageEvent<{ id: string; type: "progress"; progress: ScanProgress }>) => {
      if (event.data.id === id && event.data.type === "progress") onProgress?.(event.data.progress);
    };
    this.worker.addEventListener("message", listener);
    return new Promise((resolve, reject) => {
      this.pending.set(id, {
        resolve: (result) => {
          this.worker.removeEventListener("message", listener);
          resolve(result);
        },
        reject: (error) => {
          this.worker.removeEventListener("message", listener);
          reject(error);
        },
      });
      this.worker.postMessage({ id, type: "scan-directory", files });
    });
  }

  cancelAll(): void {
    for (const id of this.pending.keys()) this.worker.postMessage({ id, type: "cancel" });
  }

  dispose(): void {
    this.cancelAll();
    this.worker.terminate();
  }
}
