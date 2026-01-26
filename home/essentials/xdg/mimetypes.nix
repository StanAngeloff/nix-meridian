{ ... }:
{
  defaultApplications = {
    "org.gnome.eog.desktop" = [
      "image/avif"
      "image/bmp"
      "image/gif"
      "image/heic"
      "image/jpeg"
      "image/png"
      "image/svg+xml-compressed"
      "image/svg+xml"
      "image/svg+xml"
      "image/tiff"
      "image/vnd.microsoft.icon"
      "image/webp"
    ];
    "org.gnome.Papers.desktop" = [
      "application/pdf"
    ];
    "org.gnome.TextEditor.desktop" = [
      "application/x-shellscript"
      "text/plain"
      "text/x-log"
    ];
    "org.gnome.gitlab.somas.Apostrophe.desktop" = [
      "text/markdown"
    ];
    "brave-browser.desktop" = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    "thunderbird.desktop" = [
      "application/x-extension-ics"
      "message/rfc822"
      "text/calendar"
      "x-scheme-handler/mailto"
      "x-scheme-handler/webcal"
      "x-scheme-handler/webcals"
    ];
  };
}
