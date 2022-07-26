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
          });
        };
        
        pkgsWithNimble = pkgs.appendOverlays [ flake-nimble.overlay overlays.default ];
        
        packages = flake-utils.lib.flattenTree {
          ws = pkgsWithNimble.nimPackages.ws;
          patty = pkgsWithNimble.nimPackages.patty;
          karax = pkgsWithNimble.nimPackages.karax;
          jswebsockets = pkgsWithNimble.nimPackages.jswebsockets;
          telebot = pkgsWithNimble.nimPackages.telebot;
          questionable = pkgsWithNimble.nimPackages.questionable;
          
          nim = pkgs.nim;
          nimlsp = pkgs.nimlsp;

          kinoplex = pkgs.nimPackages.buildNimPackage {
            pname = "kinoplex";
            version = "0.1.0";
            src = ./.;
            propagatedBuildInputs = with packages;
              [ ws patty karax jswebsockets telebot questionable ];
          };
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
          nativeBuildInputs = with packages; [ nim nimlsp ];
          buildInputs = [ pkgs.openssl ];
        };
      });
}
