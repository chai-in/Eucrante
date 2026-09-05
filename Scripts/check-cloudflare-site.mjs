import { createHash } from "node:crypto";
import { access, readFile, readdir, stat } from "node:fs/promises";
import { dirname, join, normalize, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const site = join(root, "Site");
const required = [
  "index.html",
  "404.html",
  "styles.css",
  "robots.txt",
  "sitemap.xml",
  "assets/icon.png",
  "assets/og.png",
];

for (const path of required) {
  const file = join(site, path);
  await access(file);
  if ((await stat(file)).size === 0) {
    throw new Error(`Static asset is empty: ${path}`);
  }
}

const htmlFiles = ["index.html", "404.html"];
for (const htmlFile of htmlFiles) {
  const html = await readFile(join(site, htmlFile), "utf8");
  if (!/<title>[^<]+<\/title>/i.test(html)) {
    throw new Error(`Missing page title: ${htmlFile}`);
  }
  if (/localhost|127\.0\.0\.1/i.test(html)) {
    throw new Error(`Local-only URL found in: ${htmlFile}`);
  }

  const references = html.matchAll(/(?:href|src)=["']([^"']+)["']/gi);
  for (const [, reference] of references) {
    if (/^(?:[a-z]+:|#|\/\/)/i.test(reference)) continue;
    const pathname = reference.split(/[?#]/, 1)[0];
    if (!pathname) continue;
    const target = normalize(join(site, dirname(htmlFile), pathname));
    if (relative(site, target).startsWith("..")) {
      throw new Error(`Asset escapes Site/: ${htmlFile} -> ${reference}`);
    }
    await access(target).catch(() => {
      throw new Error(`Missing local asset: ${htmlFile} -> ${reference}`);
    });
  }
}

const homepage = await readFile(join(site, "index.html"), "utf8");
for (const requiredCopy of [
  "Download DMG",
  "not notarized",
  "Privacy &amp; Security > Open Anyway",
  "Never disable Gatekeeper",
  "Apple silicon only (arm64)",
]) {
  if (!homepage.includes(requiredCopy)) {
    throw new Error(`Missing public-DMG safety copy: ${requiredCopy}`);
  }
}

console.log("Cloudflare static-site checks passed.");

const built = join(root, "dist", "site");
const builtHTML = await readFile(join(built, "index.html"), "utf8");
const headers = await readFile(join(built, "_headers"), "utf8");
if (headers.trim() !== "/static/*\n  Cache-Control: public, max-age=31536000, immutable") {
  throw new Error("Only fingerprinted static assets may use immutable caching.");
}
if (/<script\b/i.test(builtHTML)) throw new Error("The site must remain JavaScript-free.");
let initialBytes = Buffer.byteLength(builtHTML);
for (const name of await readdir(join(built, "static"))) {
  const [, stem, hash, extension] = name.match(/^(.+)\.([a-f0-9]{16})\.(css|png)$/) ?? [];
  const data = await readFile(join(built, "static", name));
  if (!hash || createHash("sha256").update(data).digest("hex").slice(0, 16) !== hash) {
    throw new Error(`Stale asset fingerprint: ${name}`);
  }
  if (!builtHTML.includes(`static/${name}`)) throw new Error(`Unused built asset: ${name}`);
  if (stem !== "og") initialBytes += data.byteLength;
  if (stem === "icon") {
    // PNG IHDR dimensions: enough for the 38px brand at 3x, without shipping the app-size icon.
    if (data.readUInt32BE(16) !== 128 || data.readUInt32BE(20) !== 128) {
      throw new Error("Website icon must be the packaged 128px rendition.");
    }
  }
  if (extension === "css" && /@import|url\(/i.test(data.toString())) {
    throw new Error("Unexpected additional stylesheet network dependency.");
  }
}
for (const [, path] of builtHTML.matchAll(/(?:href|src)="(static\/[^"?]+)"/g)) {
  await access(join(built, path));
}
if (initialBytes > 52 * 1024) throw new Error(`Initial resource budget exceeded: ${initialBytes}`);
console.log(`Built asset hashes, cache rules, and resource budget passed (${initialBytes} bytes before HTTP compression).`);
