import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile, copyFile } from "node:fs/promises";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { transform } from "esbuild";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = join(root, "Site");
const output = join(root, "dist", "site");
await rm(output, { recursive: true, force: true });
await mkdir(join(output, "static"), { recursive: true });

const references = new Map();
for (const path of ["styles.css", "assets/icon.png", "assets/og.png"]) {
  let data = await readFile(join(source, path));
  if (extname(path) === ".css") {
    const result = await transform(data.toString(), {
      loader: "css", minify: true, target: ["safari17", "chrome120", "firefox120"],
    });
    if (result.warnings.length) throw new Error("Stylesheet minification produced warnings.");
    data = Buffer.from(result.code);
  }
  const hash = createHash("sha256").update(data).digest("hex").slice(0, 16);
  const extension = extname(path);
  const name = `${basename(path, extension)}.${hash}${extension}`;
  await writeFile(join(output, "static", name), data);
  references.set(path, `static/${name}`);
}

for (const path of ["index.html", "404.html"]) {
  let html = await readFile(join(source, path), "utf8");
  for (const [original, fingerprinted] of references) {
    html = html.replaceAll(original, fingerprinted);
  }
  await writeFile(join(output, path), html);
}
for (const path of ["robots.txt", "sitemap.xml", "_headers"]) {
  await copyFile(join(source, path), join(output, path));
}
console.log("Built fingerprinted static assets in dist/site.");
