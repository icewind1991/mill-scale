# mill-scale -- Another rust module for flakelight
# Copyright (C) 2024 Robin Appelman <robin@icewind.nl>
# SPDX-License-Identifier: MIT

{ lib, src, config, flakelight, inputs, ... }:
let
  inherit (builtins) elem readFile pathExists isAttrs attrNames;
  inherit (lib) mkDefault mkIf mkMerge mkOption warnIf assertMsg optionalAttrs types optionalString;
  inherit (lib.fileset) fileFilter toSource;
  inherit (flakelight.types) fileset;

  cargoToml = fromTOML (readFile (src + /Cargo.toml));
  tomlPackage = cargoToml.package or cargoToml.workspace.package;
  hasMsrv = tomlPackage ? rust-version;
  hasWorkspace = tomlPackage ? workspace;
  hasFeatures = cargoToml ? features && isAttrs cargoToml.features;
  hasDefaultFeatures = cargoToml ? features && cargoToml.features ? default;
  msrv = assert assertMsg hasMsrv ''"rust-version" not set in Cargo.toml''; tomlPackage.rust-version;
  tools = pkgs: with pkgs; [ cargo-edit bacon ];
  maybeWorkspace = optionalString hasWorkspace "--workspace";
in
warnIf (! builtins ? readFileType) "Unsupported Nix version in use."
{
  options = {
    extraFiles = mkOption {
      type = with types; listOf str;
      default = [ ];
    };
    fileset = mkOption {
      type = fileset;
      default = fileFilter
        (file: file.hasExt "rs" || elem file.name ([ "Cargo.toml" "Cargo.lock" ] ++ config.extraFiles))
        src;
    };
  };

  config = mkMerge [
    (mkIf (pathExists (src + /Cargo.toml)) {
      withOverlays = [
        (import inputs.rust-overlay)
        (final: { inputs, rust-bin, writeShellApplication, stdenvNoCC, ... } @ prev: rec {
          crateName = (craneLib.crateNameFromCargoToml { inherit src; }).pname;
          craneLib = (inputs.crane.mkLib final).overrideToolchain (p: p.latestRustToolchain);
          craneLibMsrv = (inputs.crane.mkLib final).overrideToolchain (p: p.msrvRustToolchain);
          cargoArtifacts = craneLib.buildDepsOnly
            {
              inherit src;
              strictDeps = true;
            };
          cargoArtifactsAllFeatures = craneLib.buildDepsOnly
            {
              inherit src;
              strictDeps = true;
              cargoExtraArgs = "--locked --all-features";
              pname = "${crateName}-all-features";
            };
          cargoArtifactsNoDefault = craneLib.buildDepsOnly
            {
              inherit src;
              strictDeps = true;
              cargoExtraArgs = "--locked --no-default-features";
              pname = "${crateName}-no-default-features";
            };
          cargoArtifactsMsrv = craneLibMsrv.buildDepsOnly
            {
              inherit src;
              strictDeps = true;
              cargoExtraArgs = "--locked --all-features";
              pname = "${crateName}-msrv";
            };
          latestRustToolchain = rust-bin.stable.latest.default;
          msrvRustToolchain = rust-bin.stable.${msrv}.default;
          miriRustToolchain = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
            extensions = [ "miri" "rust-src" ];
          });
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
        default = { craneLib, cargoArtifacts, defaultMeta }: craneLib.buildPackage {
          src = toSource { root = src; inherit (config) fileset; };
          inherit cargoArtifacts;
          doCheck = false;
          strictDeps = true;
          meta = defaultMeta;
        };
      };

      checks =
        { craneLib
        , craneLibMsrv
        , cargoArtifacts
        , cargoArtifactsMsrv
        , cargoArtifactsAllFeatures
        , cargoArtifactsNoDefault
        , crateName
        , ...
        }: {
          test = craneLib.cargoTest {
            inherit src cargoArtifacts;
            cargoExtraArgs = "--locked --all-targets --workspace";
          };
          clippy = craneLib.cargoClippy {
            inherit src cargoArtifacts;
            strictDeps = true;
            cargoClippyExtraArgs = "--all-targets ${maybeWorkspace} -- --deny warnings";
          };
        } // (optionalAttrs hasMsrv {
          msrv = craneLibMsrv.buildPackage {
            inherit src;
            pname = "${crateName}-msrv";
            cargoArtifacts = cargoArtifactsMsrv;
            strictDeps = true;
            doCheck = false;
            cargoBuildCommand = "cargo check";
            cargoExtraArgs = "--release --locked --all-targets --all-features ${maybeWorkspace}";
            installPhaseCommand = "mkdir $out";
          };
        }) // (optionalAttrs hasFeatures {
          test-all-features = craneLib.cargoTest {
            inherit src;
            pname = "${crateName}-all-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsAllFeatures;
            cargoExtraArgs = "--locked --all-targets --all-features ${maybeWorkspace}";
          };
          clippy-all-features = craneLib.cargoClippy {
            inherit src;
            pname = "${crateName}-all-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsAllFeatures;
            cargoClippyExtraArgs = "--all-targets ${maybeWorkspace} --all-features -- --deny warnings";
          };
        }) // (optionalAttrs hasDefaultFeatures {
          test-no-default-features = craneLib.cargoTest {
            inherit src;
            pname = "${crateName}-no-default-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsNoDefault;
            cargoExtraArgs = "--locked --all-targets --no-default-features ${maybeWorkspace}";
          };
          clippy-no-default-features = craneLib.cargoClippy {
            inherit src;
            pname = "${crateName}-no-default-features";
            strictDeps = true;
            cargoArtifacts = cargoArtifactsNoDefault;
            cargoClippyExtraArgs = "--all-targets ${maybeWorkspace} --no-default-features -- --deny warnings";
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
          packages = pkgs: with pkgs; [ latestRustToolchain ] ++ tools pkgs;

          env = { rustPlatform, ... }: {
            RUST_SRC_PATH = toString rustPlatform.rustLibSrc;
          };
        };
        miri = {
          packages = pkgs: with pkgs; [ miriRustToolchain cargo-edit bacon ] ++ tools pkgs;

          inherit (default) env;
        };
      } // (optionalAttrs hasMsrv {
        msrv = {
          packages = pkgs: with pkgs; [ msrvRustToolchain cargo-edit bacon ] ++ tools pkgs;

          inherit (devShells.default) env;
        };
      });

      formatters = pkgs: {
        "*.rs" = "${pkgs.rustfmt}/bin/rustfmt";
      };
    }
  ];
}
