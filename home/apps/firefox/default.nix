{
  programs.firefox = {
    enable = true;

    policies = {
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableTelemetry = true;
    };

    profiles = {
      default = {
        isDefault = true;
        settings = {
          "browser.tabs.unloadOnLowMemory" = true; # See https://support.mozilla.org/en-US/kb/unload-inactive-tabs-save-system-memory-firefox
          "browser.tabs.min_inactive_duration_before_unload" = 3600000; # Unload tabs after 1 hour of inactivity (the default is 10 minutes).
          # Usability & quality of life improvements
          #
          "middlemouse.paste" = false; # This is just stOOpid.
          "browser.urlbar.update1" = false; # Don't use the new URL bar which looks like an annoying pop up (Firefox 75+).
          "browser.urlbar.update1.interventions" = false; # If true, Firefox shows actionable tips in the URL bar when the user is searching for those actions.
          "browser.urlbar.update1.searchTips" = false; # If true, Firefox shows new users and those about to start an organic search a tip encouraging them to use the URL bar.
          "browser.urlbar.update1.view.stripHttps" = false; # Don't strip https:// from URL suggestions (Firefox 75+).
          "browser.urlbar.openViewOnFocus" = false; # Don't open the URL bar drop-down immediately on focus (Firefox 75+).
          "browser.urlbar.groupLabels.enable" = false; # Disable Firefox Suggest (sponsored suggestions).
          "browser.urlbar.trimURLs" = false; # Force Firefox to always show https:// and www. terms for URLs in address bar.
          "signon.firefoxRelay.feature" = "disabled";
          # Forms and Autofill
          "extensions.formautofill.available" = "on";
          "extensions.formautofill.creditCards.available" = true;
          "extensions.formautofill.creditCards.enabled" = true;
          "extensions.formautofill.supportedCountries" = "US,CA,BG";
          "extensions.formautofill.creditCards.supported" = "on"; # See https://hg.mozilla.org/mozilla-central/rev/229e5309bc92113ea8c696f40db0fbb56c3a33b6#l3.1
          "extensions.formautofill.creditCards.supportedCountries" = "US,CA,UK,FR,DE,BG";
          "extensions.formautofill.addresses.enabled" = true;
          "extensions.formautofill.addresses.capture.enabled" = true;
          "extensions.formautofill.addresses.supported" = "on"; # See https://hg.mozilla.org/mozilla-central/rev/229e5309bc92113ea8c696f40db0fbb56c3a33b6#l3.1
          "extensions.formautofill.addresses.supportedCountries" = "US,CA,UK,FR,DE,BG";
          "dom.forms.selectSearch" = true; # Search <select> drop-downs when they contain 41 or more items, see https://wiki.mozilla.org/QA/Dom_Forms_Select_Search
          # Development
          #
          "devtools.chrome.enabled" = true; # This enables Ctrl+Alt+Shift+J as well as the command entry in Ctrl+Shift+J.
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          # Security
          #
          "privacy.firstparty.isolate" = true;
          "dom.private-attribution.submission.enabled" = false;
          # See https://blog.mozilla.org/security/2021/05/18/introducing-site-isolation-in-firefox/
          "fission.autostart" = true;
          # See https://web.archive.org/web/20201118141821/https://blog.mozilla.org/security/2020/11/17/firefox-83-introduces-https-only-mode/
          "dom.security.https_only_mode" = true;
          "dom.security.https_only_mode_ever_enabled" = true;
          # Network
          #
          "network.dns.disableIPv6" = true; # We don't use or need IPv6.
          "network.http.http3.enabled" = true;
          # Caching
          #
          "browser.cache.memory.enable" = true;
          "browser.cache.memory.capacity" = 1048576; # 1GB
          "browser.cache.memory.max_entry_size" = 20480; # 20MB
          # Colour Management
          "gfx.color_management.mode" = 1;
          "gfx.color_management.enablev4" = true;
          # Experimental
          #
          "gfx.webrender.all" = true;
          "gfx.x11-egl.force-enabled" = true; # https://web.archive.org/web/20211112033042/https://mastransky.wordpress.com/2021/10/30/firefox-94-comes-with-egl-on-x11/#:~:text=Faster%20WebGL%20rendering
          "media.videocontrols.picture-in-picture.enabled" = true; # https://web.archive.org/web/20191203233905/https://css-tricks.com/an-introduction-to-the-picture-in-picture-web-api/#article-header-id-0
          "media.hardwaremediakeys.enabled" = true; # https://web.archive.org/web/20200324112855/https://www.ghacks.net/2020/03/23/firefox-will-soon-support-hardware-media-controls/
          "dom.media.mediasession.enabled" = true;
          "cookiebanners.service.mode" = 2; # https://bugzilla.mozilla.org/show_bug.cgi?id=1783019 | nsICookieBannerService.MODE_REJECT_OR_ACCEPT = 2
          "svg.context-properties.content.enabled" = true;
          # https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Performance-tuning#firefox
          "reader.parse-on-load.enabled" = false;
          "media.webspeech.synth.enabled" = false;
          # Firefox 131, uh!
          #
          "browser.tabs.tabmanager.enabled" = false;
          "browser.tabs.hoverPreview.enabled" = false;
          "browser.tabs.hoverPreview.showThumbnails" = false;
        };
      };
    };
  };
}
