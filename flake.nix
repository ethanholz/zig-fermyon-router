{
  inputs =
    {
      nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

      zig-overlay.url = "github:mitchellh/zig-overlay";
      zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

      gitignore.url = "github:hercules-ci/gitignore.nix";
      gitignore.inputs.nixpkgs.follows = "nixpkgs";

      flake-utils.url = "github:numtide/flake-utils";
    };

  outputs = inputs:
    let
      inherit (inputs) nixpkgs zig-overlay gitignore flake-utils;
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      inherit (gitignore.lib) gitignoreSource;
    in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zig = zig-overlay.packages.${system}."0.13.0";
      in
      rec {
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
        packages.default = packages.fermyon-router;
        packages.fermyon-router = pkgs.stdenvNoCC.mkDerivation {
          name = "fermyon-router";
          version = "main";
          src = gitignoreSource ./.;
          nativeBuildInputs = [ zig ];
          dontConfigure = true;
          dontInstall = true;
          doCheck = false;
          buildPhase = ''
            mkdir -p .cache
            ln -s ${pkgs.callPackage ./deps.nix { }} .cache/p
            zig build install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache --prefix $out -Doptimize=ReleaseFast
          '';
          checkPhase = ''
            zig build test --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache
          '';
        };
        devShell = pkgs.mkShell {
          buildInputs = [ packages.fermyon-router.nativeBuildInputs pkgs.fermyon-spin ];
        };

      }
    );
}
