import { CobaltContainer } from "./cobalt-container";
import { cobaltUpstreamPath, isCobaltProxyPath } from "./cobalt-routing";
import type { CompleteUploadBody, JobArtifact, JobManifest } from "./contracts";
import { json, problem, readJSON, readResponseJSON } from "./http";
import { artifactKey, deleteJob, getManifest, putManifest, resolutionKey } from "./storage";
import {
  RequestValidationError,
  validateCreateJob,
  validateJobID,
  validatePartNumber,
  validateSlot,
} from "./validation";

export { CobaltContainer };

const apiVersion = "1.0";

export default {
  async fetch(request, env): Promise<Response> {
    const requestID = crypto.randomUUID();
    const startedAt = Date.now();
    try {
      if (!isAuthorized(request, env)) {
        return problem(401, "access_required", "Cloudflare Access authentication is required.");
      }

      const url = new URL(request.url);
      const response = await route(request, url, env);
      response.headers.set("X-Request-ID", requestID);
      return response;
    } catch (error) {
      if (error instanceof RequestValidationError) {
        return problem(400, "invalid_request", error.message);
      }
      console.error(
        JSON.stringify({
          event: "request_failed",
          requestID,
          method: request.method,
          path: new URL(request.url).pathname,
          message: error instanceof Error ? error.message : "unknown",
        }),
      );
      return problem(500, "internal_error", "The request could not be completed.");
    } finally {
      console.log(
        JSON.stringify({
          event: "request_completed",
          requestID,
          method: request.method,
          path: new URL(request.url).pathname,
          durationMs: Date.now() - startedAt,
        }),
      );
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method === "GET" && url.pathname === "/.well-known/eucrante") {
    return json({
      product: "Eucrante",
      apiVersion,
      capabilities: ["cobalt-v11", "r2-jobs", "multipart-uploads", "range-downloads"],
      cobaltEndpoint: "/v1/cobalt/",
      jobsEndpoint: "/v1/jobs",
      retention: "until-explicit-deletion",
    });
  }

  if (url.pathname === "/v1/jobs" && request.method === "POST") {
    return createAndResolveJob(request, env);
  }

  const jobMatch = url.pathname.match(/^\/v1\/jobs\/([^/]+)$/);
  if (jobMatch?.[1]) {
    const jobID = validateJobID(jobMatch[1]);
    if (request.method === "GET") return getJob(env.JOBS, jobID);
    if (request.method === "DELETE") return removeJob(env.JOBS, jobID);
    return methodNotAllowed("GET, DELETE");
  }

  const objectMatch = url.pathname.match(/^\/v1\/jobs\/([^/]+)\/(inputs|outputs)\/([^/]+)$/);
  if (objectMatch?.[1] && objectMatch[2] && objectMatch[3]) {
    const jobID = validateJobID(objectMatch[1]);
    const role = objectMatch[2] === "inputs" ? "input" : "output";
    const slot = validateSlot(objectMatch[3]);
    if (request.method === "GET" || request.method === "HEAD") {
      return downloadArtifact(request, env.JOBS, jobID, role, slot);
    }
    if (request.method === "PUT") return putArtifact(request, env.JOBS, jobID, role, slot);
    return methodNotAllowed("GET, HEAD, PUT");
  }

  const uploadMatch = url.pathname.match(
    /^\/v1\/jobs\/([^/]+)\/(inputs|outputs)\/([^/]+)\/multipart(?:\/parts\/([^/]+)|\/(complete|abort))?$/,
  );
  if (uploadMatch?.[1] && uploadMatch[2] && uploadMatch[3]) {
    const jobID = validateJobID(uploadMatch[1]);
    const role = uploadMatch[2] === "inputs" ? "input" : "output";
    const slot = validateSlot(uploadMatch[3]);
    if (request.method === "POST" && !uploadMatch[4] && !uploadMatch[5]) {
      return startMultipart(request, env.JOBS, jobID, role, slot);
    }
    if (request.method === "PUT" && uploadMatch[4]) {
      return uploadPart(request, url, env.JOBS, jobID, role, slot, uploadMatch[4]);
    }
    if (request.method === "POST" && uploadMatch[5] === "complete") {
      return completeMultipart(request, env.JOBS, jobID, role, slot);
    }
    if (request.method === "DELETE" && uploadMatch[5] === "abort") {
      return abortMultipart(url, env.JOBS, jobID, role, slot);
    }
    return methodNotAllowed("POST, PUT, DELETE");
  }

  if (isCobaltProxyPath(url.pathname)) {
    return proxyToCobalt(request, env);
  }

  return problem(404, "not_found", "No Eucrante API route matches this request.");
}

async function createAndResolveJob(request: Request, env: Env): Promise<Response> {
  const body = validateCreateJob(await readJSON(request));
  const now = new Date().toISOString();
  const id = crypto.randomUUID();
  const sourceHost = new URL(body.request.url).hostname.toLowerCase();
  let manifest: JobManifest = {
    schemaVersion: 1,
    id,
    state: "resolving",
    preset: body.preset ?? "custom",
    sourceHost,
    createdAt: now,
    updatedAt: now,
    artifacts: [],
  };
  await putManifest(env.JOBS, manifest);

  try {
    const cobaltRequest = new Request(`${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/v1/cobalt/`, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify(body.request),
    });
    const cobaltResponse = await proxyToCobalt(cobaltRequest, env);
    const result = await readResponseJSON(cobaltResponse);
    const failed = isCobaltFailure(result) || !cobaltResponse.ok;
    manifest = {
      ...manifest,
      state: failed ? "failed" : "resolved",
      updatedAt: new Date().toISOString(),
      ...(failed ? { errorCode: cobaltErrorCode(result) } : {}),
    };
    await Promise.all([
      env.JOBS.put(resolutionKey(id), JSON.stringify(result), {
        httpMetadata: { contentType: "application/json" },
      }),
      putManifest(env.JOBS, manifest),
    ]);
    return json({ job: manifest, result }, cobaltResponse.ok ? 201 : 502);
  } catch (error) {
    manifest = {
      ...manifest,
      state: "failed",
      updatedAt: new Date().toISOString(),
      errorCode: error instanceof Error ? error.message : "resolver_failed",
    };
    await putManifest(env.JOBS, manifest);
    throw error;
  }
}

async function getJob(bucket: R2Bucket, jobID: string): Promise<Response> {
  const manifest = await getManifest(bucket, jobID);
  return manifest ? json({ job: manifest }) : problem(404, "job_not_found", "The job does not exist.");
}

async function removeJob(bucket: R2Bucket, jobID: string): Promise<Response> {
  if (!(await bucket.head(`jobs/${jobID}/manifest.json`))) {
    return problem(404, "job_not_found", "The job does not exist.");
  }
  const deletedObjects = await deleteJob(bucket, jobID);
  return json({ deleted: true, deletedObjects });
}

async function putArtifact(
  request: Request,
  bucket: R2Bucket,
  jobID: string,
  role: JobArtifact["role"],
  slot: string,
): Promise<Response> {
  const manifest = await requireManifest(bucket, jobID);
  if (!request.body) throw new RequestValidationError("An artifact body is required.");
  const key = artifactKey(jobID, role, slot);
  const object = await bucket.put(key, request.body, {
    httpMetadata: { contentType: request.headers.get("Content-Type") ?? "application/octet-stream" },
  });
  await recordArtifact(bucket, manifest, role, slot, object);
  return json({ slot, size: object.size, etag: object.etag }, 201, { ETag: object.httpEtag });
}

async function downloadArtifact(
  request: Request,
  bucket: R2Bucket,
  jobID: string,
  role: JobArtifact["role"],
  slot: string,
): Promise<Response> {
  await requireManifest(bucket, jobID);
  const object = await bucket.get(artifactKey(jobID, role, slot), {
    onlyIf: request.headers,
    range: request.headers,
  });
  if (!object) return problem(404, "artifact_not_found", "The artifact does not exist.");

  const headers = new Headers({
    "Accept-Ranges": "bytes",
    "Cache-Control": "private, no-store",
    ETag: object.httpEtag,
    "X-Content-Type-Options": "nosniff",
  });
  object.writeHttpMetadata(headers);
  if (!("body" in object)) return new Response(null, { status: 304, headers });
  const status = object.range ? 206 : 200;
  if (object.range) headers.set("Content-Range", contentRange(object.range, object.size));
  headers.set("Content-Length", String(rangeLength(object.range, object.size)));
  return new Response(request.method === "HEAD" ? null : object.body, { status, headers });
}

async function startMultipart(
  request: Request,
  bucket: R2Bucket,
  jobID: string,
  role: JobArtifact["role"],
  slot: string,
): Promise<Response> {
  await requireManifest(bucket, jobID);
  const upload = await bucket.createMultipartUpload(artifactKey(jobID, role, slot), {
    httpMetadata: { contentType: request.headers.get("Content-Type") ?? "application/octet-stream" },
  });
  return json({ uploadId: upload.uploadId, key: upload.key }, 201);
}

async function uploadPart(
  request: Request,
  url: URL,
  bucket: R2Bucket,
  jobID: string,
  role: JobArtifact["role"],
  slot: string,
  rawPartNumber: string,
): Promise<Response> {
  await requireManifest(bucket, jobID);
  if (!request.body) throw new RequestValidationError("A multipart body is required.");
  const uploadID = requireUploadID(url);
  const upload = bucket.resumeMultipartUpload(artifactKey(jobID, role, slot), uploadID);
  const part = await upload.uploadPart(validatePartNumber(rawPartNumber), request.body);
  return json(part, 201);
}

async function completeMultipart(
  request: Request,
  bucket: R2Bucket,
  jobID: string,
  role: JobArtifact["role"],
  slot: string,
): Promise<Response> {
  const manifest = await requireManifest(bucket, jobID);
  const value = (await readJSON(request)) as Partial<CompleteUploadBody>;
  if (typeof value.uploadId !== "string" || !Array.isArray(value.parts) || value.parts.length === 0) {
    throw new RequestValidationError("An upload identifier and completed parts are required.");
  }
  const parts = value.parts.map((part) => {
    if (!part || typeof part.etag !== "string") {
      throw new RequestValidationError("Each completed part requires an ETag.");
    }
    return { partNumber: validatePartNumber(String(part.partNumber)), etag: part.etag };
  });
  const upload = bucket.resumeMultipartUpload(artifactKey(jobID, role, slot), value.uploadId);
  const object = await upload.complete(parts);
  await recordArtifact(bucket, manifest, role, slot, object);
  return json({ slot, size: object.size, etag: object.etag }, 201, { ETag: object.httpEtag });
}

async function abortMultipart(
  url: URL,
  bucket: R2Bucket,
  jobID: string,
  role: JobArtifact["role"],
  slot: string,
): Promise<Response> {
  await requireManifest(bucket, jobID);
  await bucket.resumeMultipartUpload(artifactKey(jobID, role, slot), requireUploadID(url)).abort();
  return new Response(null, { status: 204 });
}

async function proxyToCobalt(request: Request, env: Env): Promise<Response> {
  const publicURL = new URL(request.url);
  const path = cobaltUpstreamPath(publicURL.pathname);
  const upstreamURL = new URL(`http://cobalt${path}${publicURL.search}`);
  const headers = new Headers(request.headers);
  for (const name of [
    "Authorization",
    "Cookie",
    "CF-Access-Jwt-Assertion",
    "CF-Access-Authenticated-User-Email",
    "CF-Connecting-IP",
  ]) {
    headers.delete(name);
  }
  const upstreamRequest = new Request(upstreamURL, {
    method: request.method,
    headers,
    body: request.method === "GET" || request.method === "HEAD" ? null : request.body,
    redirect: "manual",
  });
  const instance = env.COBALT_CONTAINER.getByName("primary");
  const response = await instance.fetch(upstreamRequest);
  const responseHeaders = new Headers(response.headers);
  responseHeaders.set("Cache-Control", "no-store");
  responseHeaders.set("X-Content-Type-Options", "nosniff");
  return new Response(response.body, { status: response.status, headers: responseHeaders });
}

async function requireManifest(bucket: R2Bucket, jobID: string): Promise<JobManifest> {
  const manifest = await getManifest(bucket, jobID);
  if (!manifest) throw new RequestValidationError("The job does not exist.");
  return manifest;
}

async function recordArtifact(
  bucket: R2Bucket,
  manifest: JobManifest,
  role: JobArtifact["role"],
  slot: string,
  object: R2Object,
): Promise<void> {
  const artifact: JobArtifact = {
    slot,
    role,
    key: object.key,
    size: object.size,
    etag: object.etag,
    ...(object.httpMetadata?.contentType ? { contentType: object.httpMetadata.contentType } : {}),
  };
  const artifacts = [...manifest.artifacts.filter((item) => !(item.role === role && item.slot === slot)), artifact];
  await putManifest(bucket, {
    ...manifest,
    state: role === "output" ? "completed" : "uploading",
    updatedAt: new Date().toISOString(),
    artifacts,
  });
}

function isAuthorized(request: Request, env: Env): boolean {
  return String(env.AUTH_MODE) === "none" || Boolean(request.headers.get("CF-Access-Jwt-Assertion"));
}

function methodNotAllowed(allow: string): Response {
  const response = problem(405, "method_not_allowed", "This method is not supported.");
  const headers = new Headers(response.headers);
  headers.set("Allow", allow);
  return new Response(response.body, { status: response.status, headers });
}

function requireUploadID(url: URL): string {
  const uploadID = url.searchParams.get("uploadId");
  if (!uploadID || uploadID.length > 1_024) throw new RequestValidationError("An upload identifier is required.");
  return uploadID;
}

function isCobaltFailure(value: unknown): boolean {
  return isRecord(value) && value.status === "error";
}

function cobaltErrorCode(value: unknown): string {
  if (isRecord(value) && isRecord(value.error) && typeof value.error.code === "string") {
    return value.error.code;
  }
  return "resolver_failed";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function contentRange(range: R2Range, total: number): string {
  if ("offset" in range && typeof range.offset === "number") {
    const length = range.length ?? total - range.offset;
    return `bytes ${range.offset}-${range.offset + length - 1}/${total}`;
  }
  const length = "suffix" in range ? range.suffix : (range.length ?? total);
  return `bytes ${total - length}-${total - 1}/${total}`;
}

function rangeLength(range: R2Range | undefined, total: number): number {
  if (!range) return total;
  if ("suffix" in range) return range.suffix;
  return range.length ?? total - (range.offset ?? 0);
}
