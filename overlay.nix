final: prev: {
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
      version = "0.1.2";
      src = ./.;
      propagatedBuildInputs = with nimfinal;
        [ ws patty karax jswebsockets telebot questionable ];
        nimBinOnly = true;
        postBuild = ''
          TMP_INC=$(mktemp -d)
          ln -s ${nimfinal.jswebsockets}/src/jswebsockets.nim "$TMP_INC/websockets.nim"
          HOME=$(mktemp -d) nim js -b:js -d:danger --experimental:dotOperators --path:"$TMP_INC" -o:static/client.js src/kino_web.nim
        '';
        postInstall =
          ''
            cp -r static $out
          '';
    };
  });
}
