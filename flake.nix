{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter-src.url = "github:numtide/nix-filter";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };
  outputs = { self, nixpkgs, flake-utils, nix-filter-src, pre-commit-hooks }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs { inherit system; };

          nix-filter = nix-filter-src.lib;
          lib = pkgs.lib;

          SOURCE_DATE_EPOCH = self.lastModified;

          dependencies = lib.importTOML ./dependencies.toml;

          rWrapperFromList = packageNames: pkgs.rWrapper.override {
            packages = lib.attrVals packageNames pkgs.rPackages;
          };

          flattenCollectLists = attrset: with lib; flatten (collect isList attrset);

          dep-packages =
            { dev ? true
            , Rgroups ? [ "build" ]
            }:
            let
              rPackageList = flattenCollectLists
                (lib.getAttrs (Rgroups ++ lib.optional dev "dev") dependencies.R_packages);
            in
            rWrapperFromList rPackageList;

          rWrapper-build = dep-packages { dev = false; };
          rWrapper-dev = dep-packages { dev = true; };

          build-packages-base = with pkgs; [
            pandoc
          ];
          build-packages-pdf = build-packages-base ++ (with pkgs; [
            texlive.combined.scheme-full
            which
            python3.pkgs.pygments
          ]);

          build-shell = pkgs.mkShell {
            inherit (self.checks.${system}.pre-commit-check) shellHook;
            inherit SOURCE_DATE_EPOCH;
            buildInputs = [
              pkgs.nixpkgs-fmt
              build-packages-pdf
              rWrapper-dev
            ];
          };

          targets = {
            "gitbook" = "bookdown::gitbook";
            "pdf" = "bookdown::pdf_book";
            "epub" = "bookdown::epub_book";
            "html" = "html_document";
            "all" = "all";
          };

          build-bookdown = { target ? null }:
            let
              name = "ASM-final-project";
              format = if target == null then null else lib.getAttr target targets;
              drvName = if target != null then "${name}-${target}" else name;
              buildInputs = [
                rWrapper-build
                (if builtins.elem target [ "gitbook" "html" ] then
                  build-packages-base
                else build-packages-pdf)
              ];
            in
            pkgs.runCommand "${drvName}"
              {
                inherit buildInputs SOURCE_DATE_EPOCH;

                src = nix-filter.filter {
                  root = ./.;
                  exclude = [
                    ".envrc"
                    ".gitignore"
                    "dependencies.toml"
                    "flake.lock"
                    "flake.nix"
                    "statement.pdf"
                  ];
                };

                TEXMFHOME = "./cache";
                TEXMFVAR = "./cache/var";

                extraParam = lib.optionalString (target != null) ''output_format='${format}' '';

              } ''
              cp -r $src/* .
              chmod -R +w .
              R -e "bookdown::render_book('.', $extraParam, output_dir='_book')"
              mv _book $out
            '';

          drvListToAttrs = list: with builtins; listToAttrs
            (map (drv: lib.nameValuePair drv.name drv) list);

          documents = lib.mapAttrs (target: format: build-bookdown { inherit target; }) targets;
          derivations = drvListToAttrs (lib.flatten (lib.attrValues documents));
        in
        {
          checks = {
            pre-commit-check = pre-commit-hooks.lib.${system}.run {
              src = ./.;
              hooks = {
                nixpkgs-fmt.enable = true;
              };
            };
          };

          devShells = {
            default = build-shell;
          };

          packages = {
            default = self.packages.${system}.ASM-final-project-pdf;
          } // derivations;
        });
}
