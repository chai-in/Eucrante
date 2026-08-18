import type { JobArtifact, JobManifest } from "./contracts";

const encoder = new TextEncoder();

export function manifestKey(jobID: string): string {
  return `jobs/${jobID}/manifest.json`;
}

export function resolutionKey(jobID: string): string {
  return `jobs/${jobID}/resolution.json`;
}

export function artifactKey(jobID: string, role: JobArtifact["role"], slot: string): string {
  return `jobs/${jobID}/${role}s/${slot}`;
}

export async function putManifest(bucket: R2Bucket, manifest: JobManifest): Promise<void> {
  await bucket.put(manifestKey(manifest.id), encoder.encode(JSON.stringify(manifest)), {
    httpMetadata: { contentType: "application/json" },
  });
}

export async function getManifest(bucket: R2Bucket, jobID: string): Promise<JobManifest | null> {
  const object = await bucket.get(manifestKey(jobID));
  return object ? object.json<JobManifest>() : null;
}

export async function deleteJob(bucket: R2Bucket, jobID: string): Promise<number> {
  const prefix = `jobs/${jobID}/`;
  let deleted = 0;
  let cursor: string | undefined;
  do {
    const page = await bucket.list({ prefix, limit: 1_000, ...(cursor ? { cursor } : {}) });
    if (page.objects.length > 0) {
      await bucket.delete(page.objects.map((object) => object.key));
      deleted += page.objects.length;
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return deleted;
}
