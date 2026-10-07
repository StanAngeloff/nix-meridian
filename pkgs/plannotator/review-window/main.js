// The review window: Plannotator's review page in a window of its own,
// inside the server's loopback-only network namespace (../isolate.sh), which is what keeps it off the network.
// The filters here are a second layer: they stop requests, popups, navigation away and WebRTC's STUN packets,
// but outside the namespace WebRTC over TCP (TURN) and WebTransport still reach any port on the review host,
// unseen by the request filter.
// package.json's desktopName gives the window the Wayland app_id "plannotator",
// which GNOME matches to plannotator.desktop for its name and icon.
// The window has no GTK frame: a title strip of its own carries the page's title and moves the window,
// and Electron draws the window buttons over its right end, as GNOME's button layout lists them.
// With GTK's frame, a line between the title bar and the page flickered when the window drew on the GPU.
// Usage: electron <this directory> <http://localhost:PORT/...>, with:
// PLANNOTATOR_WINDOW_PROFILE: the data directory (cookies, which hold Plannotator's settings, and the zoom level).
// PLANNOTATOR_WINDOW_BROWSER: the program a clicked link's URL goes to; unset or failing, the URL is copied instead.
// PLANNOTATOR_WINDOW_LOG: a file that gets one line per decision, read by tests/plannotator.
"use strict";

const { app, BaseWindow, Menu, WebContentsView, clipboard, ipcMain, nativeTheme, session } = require("electron");
const { execFile } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

function parseReviewUrl(argument) {
  try {
    const url = new URL(argument);
    if (url.protocol === "http:" && (url.hostname === "localhost" || url.hostname === "127.0.0.1")) {
      return url;
    }
  } catch {
    // Not a URL at all: refused below like any other.
  }
  return null;
}

const reviewUrl = parseReviewUrl(process.argv.at(-1));
const profilePath = process.env.PLANNOTATOR_WINDOW_PROFILE;
if (!reviewUrl || !profilePath) {
  console.error("usage: PLANNOTATOR_WINDOW_PROFILE=<directory> electron <app directory> <http://localhost:PORT/...>");
  process.exit(2);
}
const reviewOrigin = reviewUrl.origin;
const windowLogFile = process.env.PLANNOTATOR_WINDOW_LOG;

// The requests on which Plannotator decides a review: it answers them, then prints the outcome and exits 1.5 seconds later.
// Once one of them is answered, Electron outlives its window, so that Plannotator's exit ends the review as after any decision,
// rather than the launcher ending it as an interruption before the outcome is printed (../review-window.sh).
const DECISION_PATHS = new Set(["/api/feedback", "/api/exit", "/api/approve", "/api/deny"]);
let reviewDecided = false;

// The title strip, colored like GNOME's dark title bars, in GNOME's title font (system-ui is the GTK font).
// The right end leaves room for the window buttons.
const TITLE_BAR_HEIGHT = 36;
const TITLE_BAR_COLOR = "#222226";
const TITLE_COLOR = "#dededf";
const TITLE_BAR_URL = `data:text/html;charset=utf-8,${encodeURIComponent(`<!doctype html>
<body style="margin: 0; height: 100vh; padding: 0 96px; box-sizing: border-box; display: flex; align-items: center;
  justify-content: center; background: ${TITLE_BAR_COLOR}; color: ${TITLE_COLOR}; font: bold 11pt system-ui;
  cursor: default; user-select: none; -webkit-app-region: drag">
<span id="title" style="overflow: hidden; white-space: nowrap; text-overflow: ellipsis">Plannotator</span>
</body>`)}`;

function logDecision(...words) {
  if (windowLogFile) {
    fs.appendFileSync(windowLogFile, `${words.join(" ")}\n`);
  }
}

function isReviewOrigin(address) {
  try {
    return new URL(address).origin === reviewOrigin;
  } catch {
    return false;
  }
}

app.setPath("userData", profilePath);
// Every other name resolves to nothing, IP literals included (Chromium maps them too),
// so prefetching and preconnects go nowhere either.
app.commandLine.appendSwitch("host-resolver-rules", `MAP * ~NOTFOUND, EXCLUDE ${reviewUrl.hostname}`);

app.on("web-contents-created", (event, contents) => {
  contents.setWebRTCIPHandlingPolicy("disable_non_proxied_udp");
  contents.setWindowOpenHandler(({ url }) => {
    logDecision("deny", "window", url);
    return { action: "deny" };
  });
  const stayOnReviewOrigin = (navigation) => {
    if (!isReviewOrigin(navigation.url)) {
      logDecision("deny", "navigation", navigation.url);
      navigation.preventDefault();
    }
  };
  contents.on("will-navigate", stayOnReviewOrigin);
  contents.on("will-frame-navigate", stayOnReviewOrigin);
});

// preload.js sends the links the user clicks; only the review page's own frames are heard.
ipcMain.on("www-browser", (event, address) => {
  if (!isReviewOrigin(event.senderFrame?.url ?? "")) {
    return;
  }
  let url;
  try {
    url = new URL(address);
  } catch {
    return;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return;
  }
  const copyToClipboard = () => {
    logDecision("clipboard", url.href);
    clipboard.writeText(url.href);
  };
  const browserCommand = process.env.PLANNOTATOR_WINDOW_BROWSER;
  if (!browserCommand) {
    copyToClipboard();
    return;
  }
  logDecision("www-browser", url.href);
  execFile(browserCommand, [url.href], { timeout: 10_000 }, (error) => {
    if (error) {
      copyToClipboard();
    }
  });
});

app.whenReady().then(() => {
  // Dark for the page (prefers-color-scheme), which Chromium would ask the desktop's settings portal for over D-Bus,
  // hidden by the namespace.
  nativeTheme.themeSource = "dark";
  // A menu of its own for the editing, zoom and close shortcuts: Electron's default one also links to electronjs.org.
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      { role: "editMenu" },
      {
        label: "View",
        submenu: [
          { role: "reload" },
          { type: "separator" },
          { role: "resetZoom" },
          { role: "zoomIn" },
          { role: "zoomOut" },
          { type: "separator" },
          { role: "togglefullscreen" },
        ],
      },
      { role: "windowMenu" },
    ]),
  );

  const reviewSession = session.defaultSession;
  // Clipboard writes only: the page copies feedback with Ctrl+Shift+Y.
  reviewSession.setPermissionRequestHandler((contents, permission, callback) =>
    callback(permission === "clipboard-sanitized-write"),
  );
  reviewSession.setPermissionCheckHandler((contents, permission) => permission === "clipboard-sanitized-write");
  reviewSession.webRequest.onBeforeRequest((details, callback) => {
    const allowed = isReviewOrigin(details.url) || details.url === TITLE_BAR_URL;
    logDecision(allowed ? "allow" : "cancel", details.resourceType, details.url);
    callback({ cancel: !allowed });
  });
  // Runs before the page sees the answer, so before the page can close the window on it.
  reviewSession.webRequest.onHeadersReceived((details, callback) => {
    if (
      details.method === "POST" &&
      details.statusCode >= 200 &&
      details.statusCode < 300 &&
      isReviewOrigin(details.url) &&
      DECISION_PATHS.has(new URL(details.url).pathname)
    ) {
      logDecision("review-decided", details.url);
      reviewDecided = true;
    }
    callback({});
  });
  reviewSession.on("will-download", (event, item) => {
    logDecision("cancel", "download", item.getURL());
    event.preventDefault();
  });

  const reviewWindow = new BaseWindow({
    width: 1400,
    height: 900,
    title: "Plannotator",
    backgroundColor: TITLE_BAR_COLOR,
    titleBarStyle: "hidden",
    titleBarOverlay: { color: TITLE_BAR_COLOR, symbolColor: TITLE_COLOR, height: TITLE_BAR_HEIGHT },
  });
  const titleBarView = new WebContentsView({
    webPreferences: { sandbox: true, contextIsolation: true, nodeIntegration: false, spellcheck: false },
  });
  const reviewView = new WebContentsView({
    webPreferences: {
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false,
      preload: path.join(__dirname, "preload.js"),
    },
  });
  reviewWindow.contentView.addChildView(titleBarView);
  reviewWindow.contentView.addChildView(reviewView);
  // On the window's content view, laid out to the window's final size; the window's own resize event comes earlier,
  // with a size in between, and maximizing on Wayland sends none after it.
  const layOutViews = () => {
    const { width, height } = reviewWindow.contentView.getBounds();
    titleBarView.setBounds({ x: 0, y: 0, width, height: TITLE_BAR_HEIGHT });
    reviewView.setBounds({ x: 0, y: TITLE_BAR_HEIGHT, width, height: Math.max(height - TITLE_BAR_HEIGHT, 0) });
  };
  layOutViews();
  reviewWindow.contentView.on("bounds-changed", layOutViews);
  // On Wayland GNOME places new windows and ignores a position asked for; maximized is the one placement a window can ask.
  reviewWindow.maximize();

  // The page's title goes to the strip and to the window, where Alt+Tab shows it.
  const showTitle = () => {
    titleBarView.webContents
      .executeJavaScript(`document.getElementById("title").textContent = ${JSON.stringify(reviewWindow.getTitle())};`)
      .catch(() => {});
  };
  titleBarView.webContents.on("did-finish-load", showTitle);
  reviewView.webContents.on("page-title-updated", (event, title) => {
    reviewWindow.setTitle(title);
    showTitle();
  });

  // The page closing itself (window.close()) ends its view only; the window goes with it.
  reviewView.webContents.on("destroyed", () => {
    if (!reviewWindow.isDestroyed()) {
      reviewWindow.close();
    }
  });
  // A view outlives its window unless closed, and the page would keep running after a decision.
  // A view whose page closed itself has no webContents left.
  reviewWindow.on("closed", () => {
    for (const view of [titleBarView, reviewView]) {
      if (view.webContents && !view.webContents.isDestroyed()) {
        view.webContents.close();
      }
    }
  });

  titleBarView.webContents.loadURL(TITLE_BAR_URL);
  reviewView.webContents.loadURL(reviewUrl.href);
  reviewView.webContents.focus();
});

// After a decision Electron stays up without a window, however the window closed, until Plannotator's exit ends it.
app.on("window-all-closed", () => {
  if (!reviewDecided) {
    app.quit();
  }
});
