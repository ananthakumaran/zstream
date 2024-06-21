{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  nativeBuildInputs =
    [ pkgs.beam.packages.erlang_26.elixir_1_16 ];
}
