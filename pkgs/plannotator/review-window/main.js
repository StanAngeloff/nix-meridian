// The review window: Plannotator's review page in a window of its own,
// inside the server's loopback-only network namespace (../isolate.sh), which is what keeps it off the network.
// The filters here are a second layer: they stop requests, popups, navigation away and WebRTC's STUN packets,
// but outside the namespace WebRTC over TCP (TURN) and WebTransport still reach any port on the review host,
// unseen by the request filter.
// The page lives at an origin of the window's own, the same for every review, which the window serves itself:
// the page from the package's copy (../extract-bundle.js) when it knows which one, every other request by passing it to
// the server. So the page can load before the server is up (../prelaunch.sh), and is never 17 to 24 MB of HTML to parse.
// package.json's desktopName gives the window the Wayland app_id "plannotator",
// which GNOME matches to plannotator.desktop for its name and icon.
// The window has no GTK frame: a title strip of its own carries the page's title and moves the window,
// and Electron draws the window buttons over its right end, as GNOME's button layout lists them.
// With GTK's frame, a line between the title bar and the page flickered when the window drew on the GPU.
// Usage: electron <this directory> [<http://localhost:PORT/...>], with:
// PLANNOTATOR_WINDOW_PROFILE: the data directory (cookies, which hold Plannotator's settings, and the zoom level).
// PLANNOTATOR_WINDOW_HANDOFF: without a URL argument, the directory where the URL arrives later, in a file named url.
// PLANNOTATOR_WINDOW_PAGE and PLANNOTATOR_WINDOW_PAGES: the page to show (plan or review) and the directory of the
// package's split pages; unset, the page is the server's own.
// PLANNOTATOR_WINDOW_BROWSER: the program a clicked link's URL goes to; unset or failing, the URL is copied instead.
// PLANNOTATOR_WINDOW_LOG: a file that gets one line per decision, read by tests/plannotator.
// PLANNOTATOR_WINDOW_SPELLCHECK_LANGUAGE and PLANNOTATOR_WINDOW_SPELLCHECK_DICTIONARY: the page's spell-checking
// language (en-GB) and its Chromium dictionary file (en-GB-10-1.bdic); unset, spell checking is off.
"use strict";

const {
  app,
  BaseWindow,
  Menu,
  WebContentsView,
  clipboard,
  ipcMain,
  nativeTheme,
  net,
  protocol,
  session,
} = require("electron");
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

function isAppDirectory(argument) {
  try {
    return fs.realpathSync(argument) === __dirname;
  } catch {
    return false;
  }
}

const profilePath = process.env.PLANNOTATOR_WINDOW_PROFILE;
const handoffPath = process.env.PLANNOTATOR_WINDOW_HANDOFF;
// The app directory is the last argument when no URL follows it.
const reviewUrlArgument = isAppDirectory(process.argv.at(-1)) ? null : process.argv.at(-1);
const argumentReviewUrl = reviewUrlArgument === null ? null : parseReviewUrl(reviewUrlArgument);
if (!profilePath || (reviewUrlArgument === null ? !handoffPath : !argumentReviewUrl)) {
  console.error(
    "usage: PLANNOTATOR_WINDOW_PROFILE=<directory> electron <app directory> <http://localhost:PORT/...>\n" +
      "   or: PLANNOTATOR_WINDOW_PROFILE=<directory> PLANNOTATOR_WINDOW_HANDOFF=<directory> electron <app directory>",
  );
  process.exit(2);
}
// localhost: Plannotator advertises its server there, and the page's cookies, which hold its settings, are host-wide,
// so the window shares them with every review before it. The port is the window's alone; nothing listens on it.
const reviewOrigin = "http://localhost:19432";
const pageName = process.env.PLANNOTATOR_WINDOW_PAGE;
const pagesPath = process.env.PLANNOTATOR_WINDOW_PAGES;
const pageFiles =
  pageName && pagesPath
    ? {
        "/": { file: `${pageName}.html`, type: "text/html; charset=utf-8" },
        [`/__review-window.${pageName}.js`]: { file: `${pageName}.js`, type: "text/javascript; charset=utf-8" },
        [`/__review-window.${pageName}.css`]: { file: `${pageName}.css`, type: "text/css; charset=utf-8" },
      }
    : {};
const windowLogFile = process.env.PLANNOTATOR_WINDOW_LOG;
const spellcheckLanguage = process.env.PLANNOTATOR_WINDOW_SPELLCHECK_LANGUAGE;
const spellcheckDictionaryFile = process.env.PLANNOTATOR_WINDOW_SPELLCHECK_DICTIONARY;
const spellcheckEnabled = Boolean(spellcheckLanguage && spellcheckDictionaryFile);

// The server's origin: from the argument, or once the URL arrives in the handoff directory.
let serverOrigin = argumentReviewUrl?.origin ?? null;

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

function isServerOrigin(address) {
  try {
    return serverOrigin !== null && new URL(address).origin === serverOrigin;
  } catch {
    return false;
  }
}

// Resolves to the server's origin. The browser command leaves the URL in the handoff directory under its final name,
// so the file appears complete; the watch starts before the first look, so an arrival between the two is still seen.
const serverReady =
  serverOrigin !== null
    ? Promise.resolve(serverOrigin)
    : new Promise((resolve) => {
        const urlFile = path.join(handoffPath, "url");
        const takeUrl = () => {
          let text;
          try {
            text = fs.readFileSync(urlFile, "utf8").trim();
          } catch {
            return false;
          }
          const url = parseReviewUrl(text);
          // Plannotator advertises localhost, the one server name the resolver rules below let through.
          if (!url || url.hostname !== "localhost") {
            logDecision("deny", "handoff", text);
            app.exit(2);
            return true;
          }
          logDecision("handoff", url.href);
          serverOrigin = url.origin;
          resolve(serverOrigin);
          return true;
        };
        const watcher = fs.watch(handoffPath, () => {
          if (takeUrl()) {
            watcher.close();
          }
        });
        if (takeUrl()) {
          watcher.close();
        }
      });

app.setPath("userData", profilePath);
// Where Electron looks for a dictionary before it downloads one from Google's servers, which the namespace would stop.
if (spellcheckEnabled) {
  const dictionariesPath = path.join(profilePath, "Dictionaries");
  const dictionaryLinkFile = path.join(dictionariesPath, path.basename(spellcheckDictionaryFile));
  fs.mkdirSync(dictionariesPath, { recursive: true });
  fs.rmSync(dictionaryLinkFile, { force: true });
  fs.symlinkSync(spellcheckDictionaryFile, dictionaryLinkFile);
}
// Every name but the server's resolves to nothing, IP literals included (Chromium maps them too),
// so prefetching and preconnects go nowhere either. The page's own origin never reaches the resolver (see below).
app.commandLine.appendSwitch(
  "host-resolver-rules",
  `MAP * ~NOTFOUND, EXCLUDE ${argumentReviewUrl?.hostname ?? "localhost"}`,
);

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
  // The server's origin is let through for the requests the handler below passes on; one the page makes there itself
  // reaches the handler, which refuses it.
  reviewSession.webRequest.onBeforeRequest((details, callback) => {
    const allowed = isReviewOrigin(details.url) || isServerOrigin(details.url) || details.url === TITLE_BAR_URL;
    logDecision(allowed ? "allow" : "cancel", details.resourceType, details.url);
    callback({ cancel: !allowed });
  });
  // Every http request of the session comes here, and only the page's origin is served: its page from the package's copy,
  // when the window knows which, everything else from the server. Nothing ever listens on the page's origin.
  protocol.handle("http", async (request) => {
    const url = new URL(request.url);
    if (url.origin !== reviewOrigin) {
      return new Response(null, { status: 404 });
    }
    const pageFile = request.method === "GET" ? pageFiles[url.pathname] : undefined;
    if (pageFile) {
      logDecision("page", url.pathname);
      return new Response(await fs.promises.readFile(path.join(pagesPath, pageFile.file)), {
        headers: { "content-type": pageFile.type },
      });
    }
    const server = await serverReady;
    const headers = new Headers(request.headers);
    // The server accepts writes from its own page only, which to it is the page at its own origin.
    if (headers.get("origin") === reviewOrigin) {
      headers.set("origin", server);
    }
    const response = await net.fetch(`${server}${url.pathname}${url.search}`, {
      method: request.method,
      headers,
      body: request.body,
      duplex: "half",
      bypassCustomProtocolHandlers: true,
    });
    // Before the page sees the answer, so before the page can close the window on it.
    if (request.method === "POST" && response.ok && DECISION_PATHS.has(url.pathname)) {
      logDecision("review-decided", url.href);
      reviewDecided = true;
    }
    return response;
  });
  // No language until the page has loaded (below): a dictionary loaded before the page's renderer started never reaches it
  // (Electron 43), and the locale's own language would be downloaded, as it is with spell checking off.
  reviewSession.setSpellCheckerLanguages([]);
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
      spellcheck: spellcheckEnabled,
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

  if (spellcheckEnabled) {
    // A changed language is what sends the dictionary to the page's renderer, so it is cleared first on a reload.
    reviewView.webContents.on("did-finish-load", () => {
      reviewSession.setSpellCheckerLanguages([]);
      reviewSession.setSpellCheckerLanguages([spellcheckLanguage]);
    });
  }
  // Electron has no context menu of its own: this one has the spellchecker's suggestions and the editing commands.
  reviewView.webContents.on("context-menu", (event, parameters) => {
    const spellingItems = [
      ...parameters.dictionarySuggestions.map((suggestion) => ({
        label: suggestion,
        click: () => reviewView.webContents.replaceMisspelling(suggestion),
      })),
      ...(parameters.misspelledWord
        ? [
            {
              label: "Add to Dictionary",
              click: () => reviewSession.addWordToSpellCheckerDictionary(parameters.misspelledWord),
            },
            { type: "separator" },
          ]
        : []),
    ];
    Menu.buildFromTemplate([
      ...spellingItems,
      { role: "cut", enabled: parameters.editFlags.canCut },
      { role: "copy", enabled: parameters.editFlags.canCopy },
      { role: "paste", enabled: parameters.editFlags.canPaste },
      { type: "separator" },
      { role: "selectAll", enabled: parameters.editFlags.canSelectAll },
    ]).popup({ window: reviewWindow });
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
  // The server's path and query, if the window has its URL already, on the page's origin.
  reviewView.webContents.loadURL(
    new URL(argumentReviewUrl ? `${argumentReviewUrl.pathname}${argumentReviewUrl.search}` : "/", reviewOrigin).href,
  );
  reviewView.webContents.focus();
});

// After a decision Electron stays up without a window, however the window closed, until Plannotator's exit ends it.
app.on("window-all-closed", () => {
  if (!reviewDecided) {
    app.quit();
  }
});
