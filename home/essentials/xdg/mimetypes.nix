{ ... }:
{
  defaultApplications = {
    "org.gnome.Evince.desktop" = [
      "application/pdf"
    ];
    "org.gnome.TextEditor.desktop" = [
      "application/x-shellscript"
      "text/plain"
      "text/x-log"
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
