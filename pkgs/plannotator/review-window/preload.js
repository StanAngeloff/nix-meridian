// Runs before the review page, in an isolated world.
// A link the user clicks that leads off the page's origin goes to the main process, which hands it to the browser command;
// the page itself never navigates away.
// Only real input counts: a click the page synthesizes (element.click(), dispatchEvent) has isTrusted false and goes nowhere.
// Links within the page's origin, such as in-page anchors, work as usual.
"use strict";

const { ipcRenderer } = require("electron");

window.addEventListener(
  "click",
  (event) => {
    const anchor = event.target instanceof Element ? event.target.closest("a[href]") : null;
    if (!anchor) {
      return;
    }
    let url;
    try {
      url = new URL(anchor.getAttribute("href"), document.baseURI);
    } catch {
      event.preventDefault();
      return;
    }
    if (url.origin === location.origin) {
      return;
    }
    event.preventDefault();
    if (event.isTrusted) {
      ipcRenderer.send("www-browser", url.href);
    }
  },
  true,
);
