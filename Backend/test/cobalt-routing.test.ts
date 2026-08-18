import { describe, expect, it } from "vitest";
import { cobaltUpstreamPath, isCobaltProxyPath } from "../src/cobalt-routing";

describe("Cobalt routing", () => {
  it("proxies the public tunnel URL emitted by Cobalt", () => {
    expect(isCobaltProxyPath("/tunnel")).toBe(true);
    expect(cobaltUpstreamPath("/tunnel")).toBe("/tunnel");
  });

  it("maps the namespaced API routes into the container", () => {
    expect(cobaltUpstreamPath("/v1/cobalt")).toBe("/");
    expect(cobaltUpstreamPath("/v1/cobalt/")).toBe("/");
    expect(cobaltUpstreamPath("/v1/cobalt/tunnel")).toBe("/tunnel");
  });

  it("does not expose unrelated root paths to the container", () => {
    expect(isCobaltProxyPath("/itunnel")).toBe(false);
    expect(isCobaltProxyPath("/v1/cobaltx")).toBe(false);
    expect(() => cobaltUpstreamPath("/health")).toThrow("unsupported_cobalt_proxy_path");
  });
});
