import { RequestValidationError } from "./validation";

const jsonHeaders = {
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
  "X-Content-Type-Options": "nosniff",
} as const;

export function json(value: unknown, status = 200, extraHeaders?: HeadersInit): Response {
  const headers = new Headers(jsonHeaders);
  if (extraHeaders) {
    for (const [name, headerValue] of new Headers(extraHeaders)) headers.set(name, headerValue);
  }
  return Response.json(value, { status, headers });
}

export function problem(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

export async function readJSON(request: Request, maximumBytes = 65_536): Promise<unknown> {
  if (!request.body) throw new RequestValidationError("A JSON request body is required.");
  const contentType = request.headers.get("Content-Type")?.split(";", 1)[0]?.trim();
  if (contentType !== "application/json") {
    throw new RequestValidationError("Content-Type must be application/json.");
  }

  const contentLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maximumBytes) {
    throw new RequestValidationError("The request body is too large.");
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maximumBytes) {
      await reader.cancel("request body limit exceeded");
      throw new RequestValidationError("The request body is too large.");
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    throw new RequestValidationError("The request body is not valid JSON.");
  }
}

export async function readResponseJSON(response: Response, maximumBytes = 2 * 1_024 * 1_024): Promise<unknown> {
  if (!response.body) throw new Error("cobalt_response_empty");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maximumBytes) {
      await reader.cancel("response body limit exceeded");
      throw new Error("cobalt_response_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
}
