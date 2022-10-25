{
  description = "Server and mpv/web client for syncing media playback.";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    flake-nimble.url = "github:nix-community/flake-nimble";
  };

  outputs = { self, nixpkgs, flake-utils, flake-nimble }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlay = import ./overlay.nix;
        pkgs = import nixpkgs { inherit system; overlays = [ flake-nimble.overlay overlay ]; };
      in rec {
        nixosModules.kinoplex = import ./system/module.nix;
        nixosModules.default = nixosModules.kinoplex;

        overlays.default = overlay;

        packages = flake-utils.lib.flattenTree {
          inherit (pkgs.nimPackages) kinoplex;
        };
        defaultPackage = packages.kinoplex;

        apps = {
          server = {
            type = "app";
            program = "${packages.kinoplex}/bin/kino_server";
          };

          client = {
            type = "app";
            program = "${packages.kinoplex}/bin/kino_client";
          };

          telegram-bridge = {
            type = "app";
            program = "${packages.kinoplex}/bin/kino_telegram";
          };
        };
        
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ nim nimlsp ];
          buildInputs = [ pkgs.openssl ];
        };
      });
}
