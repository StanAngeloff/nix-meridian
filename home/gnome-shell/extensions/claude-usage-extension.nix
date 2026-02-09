{ inputs, pkgs, ... }:
let
  # See https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/desktops/gnome/extensions/buildGnomeExtension.nix#L11
  buildShellExtension =
    pkgs.callPackage (import "${inputs.nixpkgs}/pkgs/desktops/gnome/extensions/buildGnomeExtension.nix")
      { };
in
{
  programs.gnome-shell.extensions = [
    {
      package = buildShellExtension {
        uuid = "claude-code-usage@haletran.com";
        name = "Claude Code Usage";
        pname = "gnome-shell-extension-claude-code-usage";
        description = "Display Claude Code usage in the top panel. This extension uses anthropic.com services. This extension is not affiliated, funded, or in any way associated with Claude.";
        link = "https://extensions.gnome.org/extension/9231/claude-code-usage/";
        version = 1;
        sha256 = "sha256-G7sBxbktZii0tdpbfB0BADQI1hlTEDvpOB3mZXmaDOE=";
        # $ cat metadata.json | base64 | wl-copy
        metadata = ''
          ewogICJfZ2VuZXJhdGVkIjogIkdlbmVyYXRlZCBieSBTd2VldFRvb3RoLCBkbyBub3QgZWRpdCIs
          CiAgImRlc2NyaXB0aW9uIjogIkRpc3BsYXkgQ2xhdWRlIENvZGUgdXNhZ2UgaW4gdGhlIHRvcCBw
          YW5lbC4gVGhpcyBleHRlbnNpb24gdXNlcyBhbnRocm9waWMuY29tIHNlcnZpY2VzLiBUaGlzIGV4
          dGVuc2lvbiBpcyBub3QgYWZmaWxpYXRlZCwgZnVuZGVkLCBvciBpbiBhbnkgd2F5IGFzc29jaWF0
          ZWQgd2l0aCBDbGF1ZGUuIiwKICAiZG9uYXRpb25zIjogewogICAgImdpdGh1YiI6ICJIYWxldHJh
          biIKICB9LAogICJuYW1lIjogIkNsYXVkZSBDb2RlIFVzYWdlIiwKICAic2V0dGluZ3Mtc2NoZW1h
          IjogIm9yZy5nbm9tZS5zaGVsbC5leHRlbnNpb25zLmNsYXVkZS11c2FnZSIsCiAgInNoZWxsLXZl
          cnNpb24iOiBbCiAgICAiNDgiLAogICAgIjQ5IgogIF0sCiAgInVybCI6ICJodHRwczovL2dpdGh1
          Yi5jb20vSGFsZXRyYW4vY2xhdWRlLXVzYWdlLWV4dGVuc2lvbiIsCiAgInV1aWQiOiAiY2xhdWRl
          LWNvZGUtdXNhZ2VAaGFsZXRyYW4uY29tIiwKICAidmVyc2lvbiI6IDEKfQ==
        '';
      };
    }
  ];
}
