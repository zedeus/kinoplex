{
  description = "Server and mpv/web client for syncing media playback.";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    flake-nimble.url = "github:nix-community/flake-nimble";
  };

  outputs = { self, nixpkgs, flake-utils, flake-nimble }:
    flake-utils.lib.eachDefaultSystem (sys:
      let pkgs = nixpkgs.legacyPackages.${sys}; in
      rec {
        pkgsWithNimble = pkgs.appendOverlays [ flake-nimble.overlay overlays.default ];

        nixosModules.kinoplex = (import ./system/module.nix).override { pkgs = pkgsWithNimble; };
        nixosModules.default = nixosModules.kinoplex;

        overlays.default = final: prev: {
          nimPackages = prev.nimPackages.overrideScope' (nimfinal: nimprev: {
            stew = pkgs.nimPackages.stew;
            
            ws = nimprev.ws.overrideAttrs (oldAttrs: {
              inherit (nimprev.ws) pname version src;
              doCheck = false;
            });

            karax = nimprev.karax.overrideAttrs (oldAttrs: {
              inherit (nimprev.karax) pname version src;
              doCheck = false;
            });

            questionable = nimprev.karax.overrideAttrs (oldAttrs: {
              inherit (nimprev.questionable) pname version src;
              doCheck = false;
            });

            kinoplex = pkgs.nimPackages.buildNimPackage {
              pname = "kinoplex";
              version = "0.1.0";
              src = ./.;
              propagatedBuildInputs = with nimfinal;
                [ ws patty karax jswebsockets telebot questionable ];
            };
          });
        };

        packages = flake-utils.lib.flattenTree {
          kinoplex = pkgsWithNimble.nimPackages.kinoplex;
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
