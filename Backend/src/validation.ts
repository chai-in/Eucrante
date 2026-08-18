import { presetNames, type CreateJobBody, type PresetName } from "./contracts";

const jobIDPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const slotPattern = /^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$/i;

export class RequestValidationError extends Error {}

export function validateJobID(value: string): string {
  if (!jobIDPattern.test(value)) throw new RequestValidationError("Invalid job identifier.");
  return value.toLowerCase();
}

export function validateSlot(value: string): string {
  if (!slotPattern.test(value)) throw new RequestValidationError("Invalid artifact slot.");
  return value;
}

export function validatePartNumber(value: string): number {
  const partNumber = Number(value);
  if (!Number.isInteger(partNumber) || partNumber < 1 || partNumber > 10_000) {
    throw new RequestValidationError("Invalid multipart part number.");
  }
  return partNumber;
}

export function validateCreateJob(value: unknown): CreateJobBody {
  if (!isRecord(value) || !isRecord(value.request) || typeof value.request.url !== "string") {
    throw new RequestValidationError("A Cobalt request with a source URL is required.");
  }

  const source = validatePublicSourceURL(value.request.url);
  const preset = validatePreset(value.preset);
  return {
    request: { ...value.request, url: source.absoluteString },
    preset,
  };
}

export function validatePublicSourceURL(value: string): { absoluteString: string; host: string } {
  if (new TextEncoder().encode(value).byteLength > 8_192) {
    throw new RequestValidationError("The source URL is too long.");
  }

  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new RequestValidationError("The source URL is invalid.");
  }

  if ((url.protocol !== "https:" && url.protocol !== "http:") || !url.hostname) {
    throw new RequestValidationError("The source URL must use HTTP or HTTPS.");
  }
  if (url.username || url.password) {
    throw new RequestValidationError("The source URL must not contain credentials.");
  }
  return { absoluteString: url.toString(), host: url.hostname.toLowerCase() };
}

function validatePreset(value: unknown): PresetName {
  const preset = value ?? "custom";
  if (typeof preset !== "string" || !presetNames.includes(preset as PresetName)) {
    throw new RequestValidationError("Unknown output preset.");
  }
  return preset as PresetName;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
