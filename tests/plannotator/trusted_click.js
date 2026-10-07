// Loaded into the review window's Electron main process through NODE_OPTIONS by tests/plannotator (test_window.py).
// Once the page has rendered PLANNOTATOR_TEST_CLICK_SELECTOR, it clicks that element through Chromium's input pipeline,
// as a user's mouse would, so the page sees a trusted click.
// A click that never reaches the window's main process is sent again.
// Escape first closes whatever is drawn over the element (a fresh profile opens Plannotator's announcement dialog).
// Every Node runtime in the session loads this file, Plannotator's own Bun among them;
// only Electron's main process (process.type "browser") acts on it.
"use strict";

const fs = require("node:fs");

const selector = process.env.PLANNOTATOR_TEST_CLICK_SELECTOR;
const logFile = process.env.PLANNOTATOR_WINDOW_LOG;
const CLICK_RETRY_MILLISECONDS = 5000;

function locate(contents) {
  return contents.executeJavaScript(`(() => {
    const element = document.querySelector(${JSON.stringify(selector)});
    if (!element) return null;
    element.scrollIntoView({ block: "center" });
    const rectangle = element.getBoundingClientRect();
    const x = Math.round(rectangle.left + rectangle.width / 2);
    const y = Math.round(rectangle.top + rectangle.height / 2);
    return { x, y, onTop: element.contains(document.elementFromPoint(x, y)) };
  })()`);
}

// The window logs www-browser or clipboard once a click reaches its main process.
function clickWasHandled() {
  return fs
    .readFileSync(logFile, "utf8")
    .split("\n")
    .some((line) => line.startsWith("www-browser ") || line.startsWith("clipboard "));
}

async function clickWhenReachable(contents) {
  const target = await locate(contents);
  if (!target) {
    setTimeout(() => clickWhenReachable(contents), 250);
    return;
  }
  if (!target.onTop) {
    contents.sendInputEvent({ type: "keyDown", keyCode: "Escape" });
    contents.sendInputEvent({ type: "keyUp", keyCode: "Escape" });
    fs.appendFileSync(logFile, "test-escape\n");
    setTimeout(() => clickWhenReachable(contents), 500);
    return;
  }
  for (const type of ["mouseDown", "mouseUp"]) {
    contents.sendInputEvent({ type, x: target.x, y: target.y, button: "left", clickCount: 1 });
  }
  fs.appendFileSync(logFile, `test-click ${selector}\n`);
  // A click sent while the window is still settling is occasionally lost; if none reached the main process, click again.
  setTimeout(() => {
    if (!clickWasHandled()) {
      clickWhenReachable(contents);
    }
  }, CLICK_RETRY_MILLISECONDS);
}

if (process.type === "browser") {
  fs.appendFileSync(logFile, "test-harness loaded\n");
  // Deferred: while NODE_OPTIONS modules load, the electron module cannot be required yet.
  setImmediate(() => {
    // The review page's view, not the window's title strip.
    require("electron").app.on("web-contents-created", (event, contents) => {
      contents.once("did-finish-load", () => {
        if (contents.getURL().startsWith("http:")) {
          clickWhenReachable(contents);
        }
      });
    });
  });
}
