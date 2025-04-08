{
  description = "nix-meridian NixOS configuration";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-24.11";
    };

    nixpkgs-unstable = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    solaar = {
      url = "https://flakehub.com/f/Svenum/Solaar-Flake/*.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixvim,
      solaar,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
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
          ./modules/options
          ./configuration.nix
          solaar.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable; };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.stan.imports = [
              nixvim.homeManagerModules.nixvim
              ./modules/options
              ./modules/home-manager
              ./home
            ];
          }
        ];
      };
    };
}
