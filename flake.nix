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

    solaar-unstable = {
      url = "github:Svenum/Solaar-Flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    voxinput-flake = {
      url = "github:richiejp/VoxInput/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixvim,
      solaar-unstable,
      voxinput-flake,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs-overlay = final: prev: {
        ghostty-meridian = final.callPackage ./pkgs/ghostty/default.nix { };
      };
      pkgs-unstable = (
        import nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
          };
          overlays = [ pkgs-overlay ];
        }
      );
      voxinput-pkgs = voxinput-flake.packages.${system};
    in
    {
      nixosConfigurations.stan-latitude = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs pkgs-unstable voxinput-pkgs; };
        modules = [
          { nixpkgs.overlays = [ pkgs-overlay ]; }

          ./modules/options
          ./configuration.nix
          solaar-unstable.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable voxinput-pkgs; };
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
