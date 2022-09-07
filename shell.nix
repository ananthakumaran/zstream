let
  pkgs = import (builtins.fetchTarball {
    url =
      "https://github.com/NixOS/nixpkgs/archive/51d2625b49567149f642568509fe8406c15f71cf.tar.gz";
  }) { };
in pkgs.mkShell {
  nativeBuildInputs = [ pkgs.beam.packages.erlangR25.elixir_1_14 ];
}
