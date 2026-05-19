{
  description = "nix-meridian NixOS configuration";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-25.11";
    };

    nixpkgs-unstable = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    solaar-flake = {
      url = "github:Svenum/Solaar-Flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ghostty-flake = {
      url = "github:ghostty-org/ghostty/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixvim,
      solaar-flake,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      meridian-overlay = final: prev: {
        ghostty = final.callPackage ./pkgs/ghostty/overlay.nix {
          ghostty = inputs.ghostty-flake.packages.${system}.default;
        };
        curlconverter = final.callPackage ./pkgs/curlconverter/package.nix { };
        mcporter = final.callPackage ./pkgs/mcporter/package.nix { };
        n8n-cli = final.callPackage ./pkgs/n8n-cli/package.nix { };
        mcp-server-trello = final.callPackage ./pkgs/mcp-server-trello/package.nix { };
        slack-mcp-server = final.callPackage ./pkgs/slack-mcp-server/package.nix { };
        tig = final.callPackage ./pkgs/tig/overlay.nix {
          tig = prev.tig;
        };
      };
      pkgs-unstable = (
        import nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
          };
        }
      );
    in
    {
      nixosConfigurations.stan-latitude = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs pkgs-unstable; };
        modules = [
          {
            nixpkgs.overlays = [ meridian-overlay ];
          }
          ./modules/options
          ./configuration.nix
          solaar-flake.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable; };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.stan.imports = [
              nixvim.homeModules.nixvim
              ./modules/options
              ./modules/home-manager
              ./home
            ];
          }
        ];
      };
    };
}
