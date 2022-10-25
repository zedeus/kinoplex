{
  description = "Server and mpv/web client for syncing media playback.";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    flake-nimble.url = "github:nix-community/flake-nimble";
  };

  outputs = { self, nixpkgs, flake-utils, flake-nimble }:
    flake-utils.lib.eachDefaultSystem (sys:
      let oldPkgs = nixpkgs.legacyPackages.${sys}; in
      rec {
        pkgs = oldPkgs.appendOverlays [ flake-nimble.overlay overlays.default ];
        kinoplexModule = import ./system/module.nix;

        nixosModules.kinoplex = (kinoplexModule {
          services.kinoplex.package = pkgs.nimPackages.kinoplex;
        });

        nixosModules.default = nixosModules.kinoplex;

        overlays.default = final: prev: {
          nimPackages = prev.nimPackages.overrideScope' (nimfinal: nimprev: {
            inherit (prev) stew;

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

            ast_pattern_matching = nimprev.ast_pattern_matching.overrideAttrs (oldAttrs: {
              inherit (nimprev.ast_pattern_matching) pname version src;
              doCheck = false;
            });

            kinoplex = nimprev.buildNimPackage {
              pname = "kinoplex";
              version = "0.1.0";
              src = ./.;
              propagatedBuildInputs = with nimfinal;
                [ ws patty karax jswebsockets telebot questionable ];
            };
          });
        };

        packages = flake-utils.lib.flattenTree {
          kinoplex = pkgs.nimPackages.kinoplex;
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
