// Run by Bun at build time (package.nix) on the release binary's embedded module graph, the .bun ELF section, which objcopy dumps.
// Writes the graph's one JavaScript module, plannotator.js, which package.nix compiles again with bytecode,
// and the two pages that module serves, each split for the review window into pages/<plan|review>.{html,js,css}:
// a shell whose module script and stylesheet load from the page's own origin, and those two.
// Every assumption about the graph's layout (Bun 1.3, src/StandaloneModuleGraph.zig) is checked, so another layout fails the build.
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
const MODULE_RECORD_LENGTH = 52;
const graphLength = Number(section.readBigUInt64LE(0));
check(graphLength + 8 <= section.length, `a graph of ${graphLength} bytes in a section of ${section.length}`);
const graph = section.subarray(8, 8 + graphLength);
check(graph.subarray(graph.length - TRAILER.length).toString("latin1") === TRAILER, "no trailer at the graph's end");

// Offsets: the data's length (64 bits), the module records ({offset, length}), the entry point's index,
// the compile-time arguments ({offset, length}) and flags; all 32 bits but the first.
const offsetsStart = graph.length - TRAILER.length - OFFSETS_LENGTH;
check(Number(graph.readBigUInt64LE(offsetsStart)) === offsetsStart, "the offsets do not follow the data");
const recordsStart = graph.readUInt32LE(offsetsStart + 8);
const recordsLength = graph.readUInt32LE(offsetsStart + 12);
check(
  recordsLength === MODULE_RECORD_LENGTH,
  `module records of ${recordsLength} bytes, not one of ${MODULE_RECORD_LENGTH}`,
);
check(graph.readUInt32LE(offsetsStart + 16) === 0, "an entry point other than the one module");

// A module record starts with {offset, length} pointers to its name, contents, source map and bytecode.
const pointedTo = (pointerStart) => {
  const start = graph.readUInt32LE(pointerStart);
  return graph.subarray(start, start + graph.readUInt32LE(pointerStart + 4));
};
const moduleName = pointedTo(recordsStart).toString("utf8");
const moduleSource = pointedTo(recordsStart + 8).toString("utf8");
check(moduleName === "/$bunfs/root/plannotator-linux-x64", `a module named ${moduleName}`);
check(moduleSource.startsWith("// @bun\n"), "the module is not Bun's bundled JavaScript");
check(pointedTo(recordsStart + 24).length === 0, "the module already carries bytecode");
fs.mkdirSync(path.join(outputPath, "pages"), { recursive: true });
fs.writeFileSync(path.join(outputPath, "plannotator.js"), moduleSource);

// The server names its pages: `var planHtmlContent = dist_default;`, each bound to a template literal.
// The plan page serves every subcommand but review.
const PAGE_BINDINGS = { plan: "planHtmlContent", review: "reviewHtmlContent" };
for (const [pageName, bindingName] of Object.entries(PAGE_BINDINGS)) {
  const binding = moduleSource.match(new RegExp(`\\nvar ${bindingName} = (\\w+);\\n`));
  check(binding, `no binding ${bindingName}`);
  const declaration = `\nvar ${binding[1]} = \``;
  const literalStart = moduleSource.indexOf(declaration) + declaration.length;
  check(literalStart >= declaration.length, `no template literal ${binding[1]}`);
  let literalEnd = literalStart;
  while (moduleSource[literalEnd] !== "`") {
    check(literalEnd < moduleSource.length, `${binding[1]} never ends`);
    // An unescaped ${ would make the literal run code when evaluated below.
    check(
      !(moduleSource[literalEnd] === "$" && moduleSource[literalEnd + 1] === "{"),
      `${binding[1]} has a substitution`,
    );
    literalEnd += moduleSource[literalEnd] === "\\" ? 2 : 1;
  }
  // JavaScript itself turns the literal's escapes back into the page, exactly as the server's string holds it.
  const page = (0, eval)(`\`${moduleSource.slice(literalStart, literalEnd)}\``);

  const scripts = [...page.matchAll(/<script type="module" crossorigin>([\s\S]*?)<\/script>/g)];
  const styles = [...page.matchAll(/<style rel="stylesheet" crossorigin>([\s\S]*?)<\/style>/g)];
  check(
    scripts.length === 1 && styles.length === 1,
    `the ${pageName} page has ${scripts.length} scripts and ${styles.length} stylesheets`,
  );
  // At the origin's root, so anything they name relative to themselves resolves as it does inline.
  const shell = page
    .replace(scripts[0][0], () => `<script type="module" crossorigin src="/__review-window.${pageName}.js"></script>`)
    .replace(styles[0][0], () => `<link rel="stylesheet" crossorigin href="/__review-window.${pageName}.css">`);
  fs.writeFileSync(path.join(outputPath, "pages", `${pageName}.html`), shell);
  fs.writeFileSync(path.join(outputPath, "pages", `${pageName}.js`), scripts[0][1]);
  fs.writeFileSync(path.join(outputPath, "pages", `${pageName}.css`), styles[0][1]);
}
