// Loaded into the review window's Electron main process through NODE_OPTIONS by tests/plannotator (test_teardown.py).
// Once the page has loaded, it runs PLANNOTATOR_TEST_PAGE_SCRIPT in the page, as the page's own code would.
// Every Node runtime in the session loads this file, Plannotator's own Bun among them;
// only Electron's main process (process.type "browser") acts on it.
"use strict";

if (process.type === "browser") {
  // Deferred: while NODE_OPTIONS modules load, the electron module cannot be required yet.
  setImmediate(() => {
    // The review page's view, not the window's title strip.
    require("electron").app.on("web-contents-created", (event, contents) => {
      contents.once("did-finish-load", () => {
        if (contents.getURL().startsWith("http:")) {
          contents.executeJavaScript(process.env.PLANNOTATOR_TEST_PAGE_SCRIPT);
        }
      });
    });
  });
}
