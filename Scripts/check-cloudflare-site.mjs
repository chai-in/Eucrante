import { access, readFile, stat } from "node:fs/promises";
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
]) {
  if (!homepage.includes(requiredCopy)) {
    throw new Error(`Missing public-DMG safety copy: ${requiredCopy}`);
  }
}

console.log("Cloudflare static-site checks passed.");
