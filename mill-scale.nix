# mill-scale -- Another rust module for flakelight
# Copyright (C) 2024 Robin Appelman <robin@icewind.nl>
# SPDX-License-Identifier: MIT

{ lib, src, config, flakelight, inputs, ... }:
let
  inherit (builtins) elem readFile pathExists isAttrs attrNames match any;
  inherit (lib) map mkDefault mkIf mkMerge mkOption warnIf assertMsg optionalAttrs types optionalString genAttrs hasInfix intersectLists foldl attrVals;
  inherit (lib.fileset) fileFilter toSource;
  inherit (flakelight.types) fileset function optFunctionTo;

  filteredSrc = toSource { root = src; inherit (config) fileset; };
  cargoToml = fromTOML (readFile (src + /Cargo.toml));
  tomlPackage = cargoToml.package or cargoToml.workspace.package;
  hasMsrv = tomlPackage ? rust-version;
  hasWorkspace = tomlPackage ? workspace;
  hasFeatures = cargoToml ? features && isAttrs cargoToml.features;
  hasDefaultFeatures = cargoToml ? features && cargoToml.features ? default;
  msrv = assert assertMsg hasMsrv ''"rust-version" not set in Cargo.toml''; tomlPackage.rust-version;
  maybeWorkspace = optionalString hasWorkspace "--workspace";
  hasExamples = pathExists (src + /examples);

  cargoLockDeps =
    if pathExists (src + /Cargo.lock) then
      let
        cargoLock = fromTOML (readFile (src + /Cargo.lock));
      in
      map (package: package.name) cargoLock.package
    else [ ];
  availableAutoDeps = import ./autodeps.nix;
  detectedDeps = intersectLists cargoLockDeps (attrNames availableAutoDeps);
  mergedDetectedDeps =
    if config.autodeps then
      foldl
        (merged: dep: {
          build = merged.build ++ (availableAutoDeps.${dep}.build or [ ]);
          native = merged.native ++ (availableAutoDeps.${dep}.native or [ ]);
        })
        {
          build = [ ];
          native = [ ];
        }
        detectedDeps else {
      build = [ ];
      native = [ ];
    };
  buildDeps = pkgs: {
    buildInputs = (attrVals mergedDetectedDeps.build pkgs) ++ (config.buildInputs pkgs);
    nativeBuildInputs = with pkgs; [ pkg-config ] ++ (attrVals mergedDetectedDeps.native pkgs) ++ (config.nativeBuildInputs pkgs);
  };
in
warnIf (! builtins ? readFileType) "Unsupported Nix version in use."
{
  options = {
    extraFiles = mkOption {
      type = with types; listOf str;
      default = [ ];
    };
    extraFilesRegex = mkOption {
      type = with types; listOf str;
      default = [ ];
    };
    fileset = mkOption {
      type = fileset;
      default = fileFilter
        (file:
          file.hasExt "rs" ||
          match "snapshot__.*\.snap" file.name != null ||
          elem file.name ([ "Cargo.toml" "Cargo.lock" ] ++ config.extraFiles) ||
          any (re: match re file.name != null) config.extraFilesRegex)
        src;
    };
    crossTargets = mkOption {
      type = with types; listOf str;
      default = [ ];
    };
    buildInputs = mkOption {
      type = function;
      default = pkgs: [ ];
      description = "build inputs for the package";
    };
    nativeBuildInputs = mkOption {
      type = function;
      default = pkgs: [ ];
      description = "native build inputs for the package";
    };
    tools = mkOption {
      type = function;
      default = pkgs: with pkgs; [ cargo-edit bacon ];
      description = "extra packages to make available in the dev shells";
    };
    autodeps = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically detect (some) of the build dependencies";
    };
    packageOpts = mkOption {
      type = optFunctionTo types.attrs;
      default = {};
    };
    toolchain = mkOption {
      type = function;
      default = pkgs: pkgs.rust-bin.stable.latest.default;
      description = "rust toolchain to use";
    };
    msrvToolchain = mkOption {
      type = function;
      default = pkgs: pkgs.rust-bin.stable.${msrv}.default;
      description = "rust toolchain to use";
    };
    miriToolchain = mkOption {
      type = function;
      default = pkgs: pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
        extensions = [ "miri" "rust-src" ];
      });
      description = "rust toolchain to use";
    };
  };

  config = mkMerge [
    (mkIf (pathExists (src + /Cargo.toml)) {
      withOverlays = [
        (import inputs.rust-overlay)
        (final: { inputs, rust-bin, writeShellApplication, stdenvNoCC, ... } @ prev: rec {
          crateName = (craneLib.crateNameFromCargoToml { inherit src; }).pname;
          craneLib = (inputs.crane.mkLib final).overrideToolchain (p: p.rustToolchain);
          craneLibForTargets = targets: (inputs.crane.mkLib final).overrideToolchain (p: p.rustToolchain.override { inherit targets; });
          craneLibMsrv = (inputs.crane.mkLib final).overrideToolchain (p: p.msrvRustToolchain);
          cargoArtifacts = craneLib.buildDepsOnly
            {
              src = filteredSrc;
              strictDeps = true;
              inherit ((buildDeps final)) buildInputs nativeBuildInputs;
            };
          cargoArtifactsAllFeatures = craneLib.buildDepsOnly
            {
              src = filteredSrc;
              strictDeps = true;
              cargoExtraArgs = "--locked --all-features";
              pname = "${crateName}-all-features";
              inherit ((buildDeps final)) buildInputs nativeBuildInputs;
            };
          cargoArtifactsNoDefault = craneLib.buildDepsOnly
            {
              src = filteredSrc;
              strictDeps = true;
              cargoExtraArgs = "--locked --no-default-features";
              pname = "${crateName}-no-default-features";
              inherit ((buildDeps final)) buildInputs nativeBuildInputs;
            };
          cargoArtifactsMsrv = craneLibMsrv.buildDepsOnly
            {
              src = filteredSrc;
              strictDeps = true;
              cargoExtraArgs = "--locked --all-features";
              pname = "${crateName}-msrv";
              inherit ((buildDeps final)) buildInputs nativeBuildInputs;
            };
          rustToolchain = config.toolchain prev;
          msrvRustToolchain = config.msrvToolchain prev;
          miriRustToolchain = config.miriToolchain prev;
          cargo-expand = (writeShellApplication {
            name = "cargo-expand";
            runtimeInputs = [ prev.cargo-expand ];
            text = ''
              # shellcheck disable=SC2068
              RUSTC_BOOTSTRAP=1 cargo-expand $@
            '';
          });
          cargo-miri = (writeShellApplication {
            name = "cargo-miri";
            runtimeInputs = [ miriRustToolchain ];
            text = ''
              # shellcheck disable=SC2068
              cargo miri $@
            '';
          });
        })
      ];

      description = mkIf (tomlPackage ? description) tomlPackage.description;

      # license will need to be set if Cargo license is a complex expression
      license = mkIf (tomlPackage ? license) (mkDefault tomlPackage.license);

      pname = tomlPackage.name;

      packages = {
        default = { callPackage, craneLib, cargoArtifacts, defaultMeta, pkgs }: craneLib.buildPackage ({
          src = filteredSrc;
          inherit cargoArtifacts;
          doCheck = false;
          strictDeps = true;
          meta = defaultMeta;
          inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
        } // (config.packageOpts pkgs));
      } // (genAttrs config.crossTargets (
        target: { craneLibForTargets, cargoArtifacts, defaultMeta, callPackage, crateName, pkgs }:
          let
            targetCraneLib = craneLibForTargets [ target ];
            crossArgs = callPackage ./crossArgs.nix { } target;
          in
          targetCraneLib.buildPackage
            ({
              src = filteredSrc;
              doCheck = false;
              strictDeps = true;
              meta = defaultMeta // {
                targetPlatform = target;
                binarySuffix = crossArgs.BINARY_SUFFIX or "";
              };
              pname = "${crateName}-${target}";
              cargoExtraArgs = "--target ${target}";
              inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
            } // crossArgs // (config.packageOpts pkgs))
      ));

      outputs = {
        lib.crossMatrix = map
          (target: {
            inherit target;
            binary-suffix = optionalString (hasInfix "windows" target) ".exe";
          })
          config.crossTargets;
      };

      checks =
        { craneLib
        , craneLibMsrv
        , cargoArtifacts
        , cargoArtifactsMsrv
        , cargoArtifactsAllFeatures
        , cargoArtifactsNoDefault
        , crateName
        , pkgs
        , ...
        }: {
          test = craneLib.cargoTest {
            src = filteredSrc;
            inherit cargoArtifacts;
            cargoExtraArgs = "--locked --all-targets --workspace";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
          clippy = craneLib.cargoClippy {
            src = filteredSrc;
            inherit cargoArtifacts;
            strictDeps = true;
            cargoClippyExtraArgs = "--all-targets ${maybeWorkspace} -- --deny warnings";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
        } // (optionalAttrs hasMsrv {
          msrv = craneLibMsrv.buildPackage {
            src = filteredSrc;
            pname = "${crateName}-msrv";
            cargoArtifacts = cargoArtifactsMsrv;
            strictDeps = true;
            doCheck = false;
            cargoBuildCommand = "cargo check";
            cargoExtraArgs = "--release --locked --all-targets --all-features ${maybeWorkspace}";
            installPhaseCommand = "mkdir $out";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
        }) // (optionalAttrs hasFeatures {
          test-all-features = craneLib.cargoTest {
            src = filteredSrc;
            pname = "${crateName}-all-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsAllFeatures;
            cargoExtraArgs = "--locked --all-targets --all-features ${maybeWorkspace}";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
          clippy-all-features = craneLib.cargoClippy {
            src = filteredSrc;
            pname = "${crateName}-all-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsAllFeatures;
            cargoClippyExtraArgs = "--all-targets ${maybeWorkspace} --all-features -- --deny warnings";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
        }) // (optionalAttrs hasDefaultFeatures {
          test-no-default-features = craneLib.cargoTest {
            src = filteredSrc;
            pname = "${crateName}-no-default-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsNoDefault;
            cargoExtraArgs = "--locked --all-targets --no-default-features ${maybeWorkspace}";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
          clippy-no-default-features = craneLib.cargoClippy {
            inherit src;
            pname = "${crateName}-no-default-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsNoDefault;
            cargoClippyExtraArgs = "--all-targets ${maybeWorkspace} --no-default-features -- --deny warnings";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
        }) // (optionalAttrs hasExamples {
          examples = craneLibMsrv.buildPackage {
            src = filteredSrc;
            pname = "${crateName}-examples";
            cargoArtifacts = if hasFeatures then cargoArtifactsAllFeatures else cargoArtifacts;
            strictDeps = true;
            doCheck = false;
            cargoExtraArgs = "--examples ${optionalString hasFeatures "--all-features"} ${maybeWorkspace}";
            inherit ((buildDeps pkgs)) buildInputs nativeBuildInputs;
          };
        });

      apps = { cargo-miri, cargo-semver-checks, ... }: {
        miri = "${cargo-miri}/bin/cargo-miri";
        semver-checks = "${cargo-semver-checks}/bin/cargo-semver-checks semver-checks";
      };
    })

    rec {
      devShells = rec {
        default = {
          packages = pkgs: with pkgs; [ rustToolchain ]
            ++ (config.tools pkgs)
            ++ (buildDeps pkgs).buildInputs
            ++ (buildDeps pkgs).nativeBuildInputs;

          env = { rustPlatform, ... }: {
            RUST_SRC_PATH = toString rustPlatform.rustLibSrc;
          };
        };
        miri = {
          packages = pkgs: with pkgs; [ miriRustToolchain ]
            ++ (config.tools pkgs)
            ++ (buildDeps pkgs).buildInputs
            ++ (buildDeps pkgs).nativeBuildInputs;

          inherit (default) env;
        };
      } // (optionalAttrs hasMsrv {
        msrv = {
          packages = pkgs: with pkgs; [ msrvRustToolchain ]
            ++ (config.tools pkgs)
            ++ (buildDeps pkgs).buildInputs
            ++ (buildDeps pkgs).nativeBuildInputs;

          inherit (devShells.default) env;
        };
      });

      formatters = pkgs: {
        "*.rs" = "${pkgs.rustfmt}/bin/rustfmt";
      };
    }
  ];
}
