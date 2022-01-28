{
  description = "nim flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    flake-nimble.url = "github:nix-community/flake-nimble";
  };
  
  outputs = { self, nixpkgs, flake-utils, flake-nimble }:
    flake-utils.lib.eachDefaultSystem (sys:
      let
        pkgs = nixpkgs.legacyPackages.${sys};
        nimblePkgs = flake-nimble.packages.${sys};
      in {
        packages.dummy = pkgs.nimPackages.buildNimPackage {
          pname = "kinoplex";
          version = "0.1.0";
          src = ./.;
          buildInputs = [ ];
        };

        defaultPackage = self.packages.${sys}.dummy;
      });
}
