import { describe, expect, it } from "vitest";

import {
  RequestValidationError,
  validateCreateJob,
  validateJobID,
  validatePartNumber,
  validatePublicSourceURL,
  validateSlot,
} from "../src/validation";

describe("request validation", () => {
  it("normalizes valid job input", () => {
    const value = validateCreateJob({
      request: { url: "https://Example.com/watch?v=1", downloadMode: "auto" },
      preset: "apple-video-best",
    });
    expect(value.request.url).toBe("https://example.com/watch?v=1");
    expect(value.preset).toBe("apple-video-best");
  });

  it("rejects credentials and non-HTTP source URLs", () => {
    expect(() => validatePublicSourceURL("https://user:secret@example.com/video")).toThrow(
      RequestValidationError,
    );
    expect(() => validatePublicSourceURL("file:///tmp/video.mp4")).toThrow(RequestValidationError);
  });

  it("constrains path identifiers", () => {
    expect(validateJobID("8f4f0f0e-926d-4ceb-a7ec-4b7fd91a2054")).toContain("8f4f0f0e");
    expect(() => validateJobID("../other-job")).toThrow(RequestValidationError);
    expect(validateSlot("verified-output.m4a")).toBe("verified-output.m4a");
    expect(() => validateSlot("../manifest.json")).toThrow(RequestValidationError);
  });

  it("accepts only valid multipart part numbers", () => {
    expect(validatePartNumber("1")).toBe(1);
    expect(validatePartNumber("10000")).toBe(10_000);
    expect(() => validatePartNumber("0")).toThrow(RequestValidationError);
    expect(() => validatePartNumber("1.5")).toThrow(RequestValidationError);
  });
});
