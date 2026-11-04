// Run by Bun at build time (package.nix) on the release binary's embedded files, the .bun ELF section, which objcopy dumps.
// Writes the review window's copies of the two pages the server serves, plan and review, as the server unpacks them:
// each page's shell at <plan|review>/index.html, the files it loads from /assets/ under the same paths below it,
// and <plan|review>.json, which maps every path the window serves to its file and content type (review-window/main.js).
// Every assumption about the section's layout (Bun 1.4, src/standalone_graph/StandaloneModuleGraph.rs)
// and about the pages' packing (Plannotator's packages/shared/packed-app.ts) is checked, so another layout fails the build.
// Usage: bun extract-bundle.js <.bun section file> <output directory>
"use strict";

const fs = require("node:fs");
const path = require("node:path");

function check(condition, message) {
  if (!condition) {
    console.error(`extract-bundle: ${message}`);
    process.exit(1);
  }
}

const [sectionFile, outputPath] = process.argv.slice(2);
check(sectionFile && outputPath, "usage: bun extract-bundle.js <.bun section file> <output directory>");
const section = fs.readFileSync(sectionFile);

// The section: the graph's length (64 bits), then the graph, whose end is a table of offsets and a trailer.
const TRAILER = "\n---- Bun! ----\n";
const OFFSETS_LENGTH = 32;
const FILE_RECORD_LENGTH = 52;
const graphLength = Number(section.readBigUInt64LE(0));
check(graphLength + 8 <= section.length, `a graph of ${graphLength} bytes in a section of ${section.length}`);
const graph = section.subarray(8, 8 + graphLength);
check(graph.subarray(graph.length - TRAILER.length).toString("latin1") === TRAILER, "no trailer at the graph's end");

// Offsets: the data's length (64 bits), the file records ({offset, length}), the entry point's index,
// the compile-time arguments ({offset, length}) and flags; all 32 bits but the first.
const offsetsStart = graph.length - TRAILER.length - OFFSETS_LENGTH;
check(Number(graph.readBigUInt64LE(offsetsStart)) === offsetsStart, "the offsets do not follow the data");
const recordsStart = graph.readUInt32LE(offsetsStart + 8);
const recordsLength = graph.readUInt32LE(offsetsStart + 12);
check(
  recordsLength > 0 && recordsLength % FILE_RECORD_LENGTH === 0,
  `file records of ${recordsLength} bytes, not a multiple of ${FILE_RECORD_LENGTH}`,
);
check(graph.readUInt32LE(offsetsStart + 16) === 0, "an entry point other than the first file");

// A file record starts with {offset, length} pointers to its name and its contents.
const pointedTo = (pointerStart) => {
  const start = graph.readUInt32LE(pointerStart);
  const length = graph.readUInt32LE(pointerStart + 4);
  check(start + length <= offsetsStart, `a pointer to ${length} bytes at ${start}, past the data's ${offsetsStart}`);
  return graph.subarray(start, start + length);
};
const files = new Map();
for (let recordStart = recordsStart; recordStart < recordsStart + recordsLength; recordStart += FILE_RECORD_LENGTH) {
  files.set(pointedTo(recordStart).toString("utf8"), pointedTo(recordStart + 8));
}
const [serverName, serverFile] = files.entries().next().value;
check(serverName === "/$bunfs/root/plannotator-linux-x64", `a first file named ${serverName}`);
const serverSource = serverFile.toString("utf8");
check(serverSource.startsWith("// @bun\n"), "the first file is not Bun's bundled JavaScript");

// The server names its pages' files: `var planHtmlContent = embeddedPage(dist_default);`,
// with `var dist_default = "/$bunfs/root/index-pg9a28de.html";`. The plan page serves every subcommand but review.
const PAGE_BINDINGS = { plan: "planHtmlContent", review: "reviewHtmlContent" };
// A packed page: its shell, the marker, an index of the files it loads as one line of JSON
// ({"/assets/<name>": {type, start, end, base64}}), then their contents, at offsets counted from the line after the index.
const PACKED_ASSETS_MARKER = "<plaintext hidden><!--plannotator:packed-assets-->";
const ASSET_PATH = /^\/assets\/\w[\w.-]*$/;
for (const [pageName, bindingName] of Object.entries(PAGE_BINDINGS)) {
  const binding = serverSource.match(new RegExp(`\\nvar ${bindingName} = embeddedPage\\((\\w+)\\);\\n`));
  check(binding, `no binding ${bindingName}`);
  const fileName = serverSource.match(new RegExp(`\\nvar ${binding[1]} = "(/\\$bunfs/root/[\\w.-]+\\.html)";\\n`));
  check(fileName, `no file name ${binding[1]}`);
  const pageFile = files.get(fileName[1]);
  check(pageFile, `no file ${fileName[1]}`);
  // A string, as the server reads it, since the index counts in its UTF-16 code units.
  const page = pageFile.toString("utf8");
  const markerAt = page.indexOf(PACKED_ASSETS_MARKER);
  check(markerAt >= 0, `the ${pageName} page is not packed`);
  const indexStart = markerAt + PACKED_ASSETS_MARKER.length;
  const dataStart = page.indexOf("\n", indexStart) + 1;
  check(dataStart > 0, `the ${pageName} page's index never ends`);
  let index;
  try {
    index = JSON.parse(page.slice(indexStart, dataStart - 1));
  } catch {
    check(false, `the ${pageName} page's index is not JSON`);
  }
  const dataLength = page.length - dataStart;

  const shell = page.slice(0, markerAt);
  fs.mkdirSync(path.join(outputPath, pageName, "assets"), { recursive: true });
  fs.writeFileSync(path.join(outputPath, pageName, "index.html"), shell);
  const manifest = { "/": { file: `${pageName}/index.html`, type: "text/html; charset=utf-8" } };
  for (const [assetPath, entry] of Object.entries(index)) {
    check(ASSET_PATH.test(assetPath), `the ${pageName} page packs ${assetPath}`);
    check(
      typeof entry.type === "string" &&
        Number.isInteger(entry.start) &&
        Number.isInteger(entry.end) &&
        0 <= entry.start &&
        entry.start <= entry.end &&
        entry.end <= dataLength &&
        (entry.base64 === undefined || entry.base64 === true),
      `the ${pageName} page's entry for ${assetPath}: ${JSON.stringify(entry)}`,
    );
    const content = page.slice(dataStart + entry.start, dataStart + entry.end);
    // The bytes the server sends, uncompressed: binary files packed as base64, text as itself.
    const bytes = entry.base64 ? Buffer.from(content, "base64") : Buffer.from(content, "utf8");
    fs.writeFileSync(path.join(outputPath, pageName, assetPath), bytes);
    manifest[assetPath] = { file: `${pageName}${assetPath}`, type: entry.type };
  }
  // The page's module script must be one of them, or the window would wait for the server to load it.
  const scripts = [...shell.matchAll(/<script type="module" crossorigin src="([^"]*)"><\/script>/g)];
  check(
    scripts.length === 1 && Object.hasOwn(manifest, scripts[0][1]),
    `the ${pageName} page's shell has ${scripts.length} module scripts, or one it does not pack`,
  );
  fs.writeFileSync(path.join(outputPath, `${pageName}.json`), JSON.stringify(manifest));
}
