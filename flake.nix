{
  description = "NixOS fleet deployed with deploy-rs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, deploy-rs, sops-nix, ... }:
    let
      system = "x86_64-linux";
      # Add a machine here (plus a ./<name>/configuration.nix) and it's deployable.
      hosts = [ "paleo" "enneacraft" ];
      genHosts = f: nixpkgs.lib.genAttrs hosts f;
    in
    {
      nixosConfigurations = genHosts (name: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit nixpkgs-unstable; };
        modules = [
          sops-nix.nixosModules.sops
          ./common/sops.nix
          ./common/deploy.nix
          ./common/base.nix
          ./${name}/configuration.nix
        ];
      });

      # Hostnames resolve using Tailscale MagicDNS.
      deploy.nodes = genHosts (name: {
        hostname = name;
        sshUser = "root";
        confirmTimeout = 120;
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.${name};
        };
      });

      checks = builtins.mapAttrs (_: lib: lib.deployChecks self.deploy) deploy-rs.lib;

      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = [
          deploy-rs.packages.${system}.default
          nixpkgs.legacyPackages.${system}.sops
          nixpkgs.legacyPackages.${system}.age
          nixpkgs.legacyPackages.${system}.ssh-to-age
        ];
      };
    };
}
