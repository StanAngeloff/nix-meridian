// Loaded into the review window's Electron main process through NODE_OPTIONS by tests/plannotator (test_window.py).
// Once the review page has loaded, it adds a textarea over the page, types a misspelled word into it through Chromium's
// input pipeline and right-clicks the word, as a user would. It logs what the context menu gets, and the session's
// dictionary events, a download among them.
// A right-click is sent again until one gets the misspelled word: one sent as the page loads is occasionally lost,
// and one that comes before the page's spellchecker has marked the word gets no suggestions.
// Escape first closes whatever is drawn over the field or holds the focus (a fresh profile opens Plannotator's
// announcement dialog, which also turns off pointer events outside itself).
// Every Node runtime in the session loads this file, Plannotator's own Bun among them;
// only Electron's main process (process.type "browser") acts on it.
"use strict";

const fs = require("node:fs");

const logFile = process.env.PLANNOTATOR_WINDOW_LOG;
const MISSPELLED_WORD = "Speling";
const FIELD_ID = "plannotator-test-spelling";
// Inside the field's first word: the field sits at 10,10 and its monospace letters are 12 pixels wide.
const WORD_POSITION = { x: 40, y: 25 };
const RETRY_MILLISECONDS = 1000;
let misspellingFound = false;

function log(line) {
  fs.appendFileSync(logFile, `${line}\n`);
}

function focusField(contents) {
  return contents.executeJavaScript(`(() => {
    let field = document.getElementById(${JSON.stringify(FIELD_ID)});
    if (!field) {
      field = document.createElement("textarea");
      field.id = ${JSON.stringify(FIELD_ID)};
      field.style.cssText = "position: fixed; left: 10px; top: 10px; width: 400px; height: 100px; margin: 0;" +
        " z-index: 2147483647; font: 20px monospace";
      document.body.appendChild(field);
    }
    field.focus();
    return {
      reachable: document.activeElement === field &&
        document.elementFromPoint(${WORD_POSITION.x}, ${WORD_POSITION.y}) === field,
      empty: field.value === "",
    };
  })()`);
}

async function typeAndRightClick(contents) {
  const field = await focusField(contents);
  if (!field.reachable) {
    contents.sendInputEvent({ type: "keyDown", keyCode: "Escape" });
    contents.sendInputEvent({ type: "keyUp", keyCode: "Escape" });
    log("test-escape");
  } else {
    if (field.empty) {
      contents.insertText(`${MISSPELLED_WORD} `);
    }
    for (const type of ["mouseDown", "mouseUp"]) {
      contents.sendInputEvent({ type, ...WORD_POSITION, button: "right", clickCount: 1 });
    }
  }
  setTimeout(() => {
    if (!misspellingFound) {
      typeAndRightClick(contents);
    }
  }, RETRY_MILLISECONDS);
}

if (process.type === "browser") {
  // Deferred: while NODE_OPTIONS modules load, the electron module cannot be required yet.
  setImmediate(() => {
    const { app } = require("electron");
    // Before the window's own code runs, so no dictionary event is missed.
    app.on("session-created", (session) => {
      for (const eventName of ["spellcheck-dictionary-initialized", "spellcheck-dictionary-download-begin"]) {
        session.on(eventName, (event, languageCode) => log(`test-${eventName} ${languageCode}`));
      }
    });
    // The review page's view, not the window's title strip.
    app.on("web-contents-created", (event, contents) => {
      contents.once("did-finish-load", () => {
        if (!contents.getURL().startsWith("http:")) {
          return;
        }
        contents.on("context-menu", (contextMenuEvent, parameters) => {
          if (parameters.misspelledWord !== "" && !misspellingFound) {
            misspellingFound = true;
            log(`test-context-menu ${parameters.misspelledWord} ${parameters.dictionarySuggestions.join(",")}`);
          }
        });
        typeAndRightClick(contents);
      });
    });
  });
}
