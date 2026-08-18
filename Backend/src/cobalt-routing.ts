const cobaltPrefix = "/v1/cobalt";

export function isCobaltProxyPath(pathname: string): boolean {
  return (
    pathname === cobaltPrefix ||
    pathname.startsWith(`${cobaltPrefix}/`) ||
    pathname === "/tunnel"
  );
}

export function cobaltUpstreamPath(pathname: string): string {
  if (pathname === "/tunnel") return pathname;
  if (pathname === cobaltPrefix) return "/";
  if (pathname.startsWith(`${cobaltPrefix}/`)) {
    return pathname.slice(cobaltPrefix.length);
  }
  throw new Error("unsupported_cobalt_proxy_path");
}
