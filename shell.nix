{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  nativeBuildInputs = [ pkgs.beam.packages.erlang_27.elixir_1_18 ];
}
