{
  description = "tour.nvim development and headless tests (Neovim 0.13)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    neovim.url = "github:nix-community/neovim-nightly-overlay";
    neovim.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, neovim }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      each = nixpkgs.lib.genAttrs systems;
      packages = system: import nixpkgs { inherit system; };
      editor = system: neovim.packages.${system}.default;
    in {
      devShells = each (system: let pkgs = packages system; in {
        default = pkgs.mkShell {
          packages = [ (editor system) pkgs.lua-language-server pkgs.stylua pkgs.selene pkgs.git pkgs.check-jsonschema ];
        };
      });
      checks = each (system: let pkgs = packages system; in {
        tests = pkgs.runCommand "tour-tests" { nativeBuildInputs = [ (editor system) pkgs.check-jsonschema ]; } ''
          export HOME="$TMPDIR" XDG_STATE_HOME="$TMPDIR/state"
          cp -r ${self} source
          chmod -R u+w source
          cd source
          check-jsonschema --schemafile schema/tour.schema.json examples/*.json
          nvim --headless -u NONE -i NONE -l tests/run.lua
          touch "$out"
        '';
        style = pkgs.runCommand "tour-style" { nativeBuildInputs = [ pkgs.stylua pkgs.selene ]; } ''
          cd ${self}
          stylua --check lua plugin tests examples
          selene lua plugin tests examples
          touch "$out"
        '';
      });
    };
}
