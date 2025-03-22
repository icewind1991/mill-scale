# mill-scale -- Another rust module for flakelight
# Copyright (C) 2024 Robin Appelman <robin@icewind.nl>
# SPDX-License-Identifier: MIT
{
  lib,
  src,
  config,
  flakelight,
  inputs,
  ...
}: let
  inherit (builtins) elem readFile pathExists match any concatLists;
  inherit (lib) getExe map mkDefault mkIf mkMerge mkOption warnIf optionalAttrs types optionalString genAttrs hasInfix optionals;
  inherit (lib.fileset) fileFilter toSource unions;
  inherit (flakelight.types) fileset function optFunctionTo;

  filteredSrc = toSource {
    root = src;
    fileset = unions (config.extraPaths ++ [config.fileset]);
  };

  cargoToml = fromTOML (readFile (src + /Cargo.toml));
  cargoMeta = (import ./cargo-meta.nix {inherit lib;}) cargoToml;
  inherit (cargoMeta) tomlPackage hasMsrv hasWorkspace hasNonDefaultFeatures hasDefaultFeatures msrv;

  maybeWorkspace = optionalString hasWorkspace "--workspace";
  hasExamples = pathExists (src + /examples);
  hasDefaultPackage = pathExists (src + /nix/package.nix);

  autoDeps = import ./autodeps {inherit lib src config;};
  buildDeps = pkgs: rec {
    buildInputs = (autoDeps pkgs).buildInputs ++ (config.buildInputs pkgs);
    nativeBuildInputs = (autoDeps pkgs).nativeBuildInputs ++ (config.nativeBuildInputs pkgs);
    runtimeInputs = (autoDeps pkgs).runtimeInputs ++ (config.runtimeInputs pkgs);
    env =
      (autoDeps pkgs).env
      // (config.buildEnv pkgs)
      // {
        LD_LIBRARY_PATH = "/run/opengl-driver/lib/:${lib.makeLibraryPath runtimeInputs}";
      };
  };
  autoTools = let
    definitions = import ./autotools.nix;
    perDependency = map (dep: definitions.${dep} or []) (cargoMeta.dependencies ++ cargoMeta.dev-dependencies);
    all = concatLists perDependency;
  in
    pkgs: map (pkgName: pkgs.${pkgName}) all;
in
  warnIf (! builtins ? readFileType) "Unsupported Nix version in use."
  {
    options = {
      extraFiles = mkOption {
        type = with types; listOf str;
        default = [];
      };
      extraFilesRegex = mkOption {
        type = with types; listOf str;
        default = [];
      };
      extraPaths = mkOption {
        type = with types; listOf path;
        default = [];
      };
      fileset = mkOption {
        type = fileset;
        default =
          fileFilter
          (file:
            file.hasExt "rs"
            || match "snapshot__.*\.snap" file.name != null
            || elem file.name (["Cargo.toml" "Cargo.lock"] ++ config.extraFiles)
            || any (re: match re file.name != null) config.extraFilesRegex)
          src;
      };
      crossTargets = mkOption {
        type = with types; listOf str;
        default = [];
      };
      buildInputs = mkOption {
        type = function;
        default = pkgs: [];
        description = "build inputs for the package";
      };
      nativeBuildInputs = mkOption {
        type = function;
        default = pkgs: [];
        description = "native build inputs for the package";
      };
      buildEnv = mkOption {
        type = function;
        default = pkgs: {};
        description = "build environent variables for the package";
      };
      runtimeInputs = mkOption {
        type = function;
        default = pkgs: [];
        description = "runtime inputs for the package";
      };
      tools = mkOption {
        type = function;
        default = pkgs: with pkgs; [cargo-edit bacon];
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
        description = "rust toolchain to use for msrv check";
      };
      miriToolchain = mkOption {
        type = function;
        default = pkgs:
          pkgs.rust-bin.selectLatestNightlyWith (toolchain:
            toolchain.default.override {
              extensions = ["miri" "rust-src"];
            });
        description = "rust toolchain to use for miri";
      };
      cargoTest = mkOption {
        type = types.bool;
        default = true;
        description = "create a check for `cargo test`";
      };
    };

    config = mkMerge [
      (mkIf (pathExists (src + /Cargo.toml)) {
        withOverlays = [
          (import inputs.rust-overlay)
          (final: {
              inputs,
              rust-bin,
              writeShellApplication,
              stdenvNoCC,
              ...
            } @ prev: rec {
              commonCraneArgs =
                {
                  src = filteredSrc;
                  strictDeps = true;
                  doCheck = false;
                  inherit ((buildDeps final)) buildInputs nativeBuildInputs;
                }
                // (buildDeps final).env;
              allFeaturesCraneArgs =
                commonCraneArgs
                // {
                  cargoExtraArgs = "--locked --all-features ${maybeWorkspace}";
                  pname = "${crateName}-all-features";
                };
              noDefaultFeaturesCraneArgs =
                commonCraneArgs
                // {
                  cargoExtraArgs = "--locked --no-default-features ${maybeWorkspace}";
                  pname = "${crateName}-all-features";
                };
              msrvCraneArgs =
                commonCraneArgs
                // {
                  cargoExtraArgs = "--locked --all-features ${maybeWorkspace}";
                  pname = "${crateName}-msrv";
                };

              crateName = (craneLib.crateNameFromCargoToml {inherit src;}).pname;
              craneLib = (inputs.crane.mkLib final).overrideToolchain (p: p.rustToolchain);
              craneLibForTargets = targets: (inputs.crane.mkLib final).overrideToolchain (p: p.rustToolchain.override {inherit targets;});
              craneLibMsrv = (inputs.crane.mkLib final).overrideToolchain (p: p.msrvRustToolchain);

              cargoArtifacts = craneLib.buildDepsOnly commonCraneArgs;
              cargoArtifactsAllFeatures = craneLib.buildDepsOnly allFeaturesCraneArgs;
              cargoArtifactsNoDefault = craneLib.buildDepsOnly noDefaultFeaturesCraneArgs;
              cargoArtifactsMsrv = craneLibMsrv.buildDepsOnly msrvCraneArgs;

              rustToolchain = config.toolchain prev;
              msrvRustToolchain = config.msrvToolchain prev;
              miriRustToolchain = config.miriToolchain prev;
              cargo-expand = writeShellApplication {
                name = "cargo-expand";
                runtimeInputs = [prev.cargo-expand];
                text = ''
                  # shellcheck disable=SC2068
                  RUSTC_BOOTSTRAP=1 cargo-expand $@
                '';
              };
              cargo-miri = writeShellApplication {
                name = "cargo-miri";
                runtimeInputs = [miriRustToolchain];
                text = ''
                  # shellcheck disable=SC2068
                  cargo miri $@
                '';
              };
            })
        ];

        description = mkIf (tomlPackage ? description) tomlPackage.description;

        # license will need to be set if Cargo license is a complex expression
        license = mkIf (tomlPackage ? license) (mkDefault tomlPackage.license);

        pname = tomlPackage.name;

        packages =
          (optionalAttrs (!hasDefaultPackage) {
            default = {
              craneLib,
              cargoArtifacts,
              defaultMeta,
              commonCraneArgs,
              pkgs,
            }:
              craneLib.buildPackage (commonCraneArgs
                // {
                  inherit cargoArtifacts;
                  meta = defaultMeta;
                }
                // (config.packageOpts pkgs)
                // (buildDeps pkgs).env);
          })
          // (genAttrs config.crossTargets (
            target: {
              craneLibForTargets,
              cargoArtifacts,
              defaultMeta,
              callPackage,
              crateName,
              commonCraneArgs,
              pkgs,
            }: let
              targetCraneLib = craneLibForTargets [target];
              crossArgs = callPackage ./crossArgs.nix {} target;
            in
              targetCraneLib.buildPackage
              (commonCraneArgs
                // {
                  meta =
                    defaultMeta
                    // {
                      targetPlatform = target;
                      binarySuffix = crossArgs.BINARY_SUFFIX or "";
                    };
                  pname = "${crateName}-${target}";
                  cargoExtraArgs = "--target ${target}";
                }
                // crossArgs
                // (config.packageOpts pkgs))
              // (buildDeps pkgs).env
          ));

        outputs = {
          lib.crossMatrix =
            map
            (target: {
              inherit target;
              binary-suffix = optionalString (hasInfix "windows" target) ".exe";
            })
            config.crossTargets;
        };

        checks = {
          craneLib,
          craneLibMsrv,
          cargoArtifacts,
          cargoArtifactsMsrv,
          cargoArtifactsAllFeatures,
          cargoArtifactsNoDefault,
          crateName,
          commonCraneArgs,
          allFeaturesCraneArgs,
          noDefaultFeaturesCraneArgs,
          msrvCraneArgs,
          pkgs,
          ...
        }: let
          packageOpts = config.packageOpts pkgs // (buildDeps pkgs).env;
        in
          {
            clippy = craneLib.cargoClippy (commonCraneArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
              // packageOpts);
          }
          // (optionalAttrs config.cargoTest {
            test = craneLib.cargoTest (commonCraneArgs
              // {
                inherit cargoArtifacts;
                doCheck = true;
                cargoExtraArgs = "--locked --all-targets ${maybeWorkspace}";
              }
              // packageOpts);
          })
          // (optionalAttrs hasMsrv
            {
              msrv =
                craneLibMsrv.buildPackage
                (msrvCraneArgs
                  // {
                    pname = "${crateName}-msrv";
                    cargoArtifacts = cargoArtifactsMsrv;
                    cargoBuildCommand = "cargo check";
                    cargoExtraArgs = "--release --locked --all-targets --all-features ${maybeWorkspace}";
                    installPhaseCommand = "mkdir $out";
                  }
                  // packageOpts);
            })
          // (optionalAttrs (hasNonDefaultFeatures && config.cargoTest) {
            test-all-features = craneLib.cargoTest (allFeaturesCraneArgs
              // {
                cargoArtifacts = cargoArtifactsAllFeatures;
                doCheck = true;
              }
              // packageOpts);
          })
          // (optionalAttrs hasNonDefaultFeatures {
            clippy-all-features = craneLib.cargoClippy (allFeaturesCraneArgs
              // {
                cargoArtifacts = cargoArtifactsAllFeatures;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
              // packageOpts);
          })
          // (optionalAttrs (hasDefaultFeatures && config.cargoTest) {
            test-no-default-features = craneLib.cargoTest (noDefaultFeaturesCraneArgs
              // {
                cargoArtifacts = cargoArtifactsNoDefault;
                doCheck = true;
              }
              // packageOpts);
          })
          // (optionalAttrs hasDefaultFeatures {
            clippy-no-default-features = craneLib.cargoClippy (noDefaultFeaturesCraneArgs
              // {
                cargoArtifacts = cargoArtifactsNoDefault;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
              // packageOpts);
          })
          // (optionalAttrs hasExamples {
            examples = craneLibMsrv.buildPackage (commonCraneArgs
              // {
                pname = "${crateName}-examples";
                cargoExtraArgs = "--examples ${optionalString hasNonDefaultFeatures "--all-features"} ${maybeWorkspace}";
              }
              // packageOpts);
          });

        apps = {
          cargo-miri,
          cargo-semver-checks,
          ...
        }: {
          miri = "${cargo-miri}/bin/cargo-miri";
          semver-checks = "${cargo-semver-checks}/bin/cargo-semver-checks semver-checks";
        };
      })

      rec {
        devShells =
          rec {
            default = {
              packages = pkgs:
                with pkgs;
                  [rustToolchain]
                  ++ (config.tools pkgs)
                  ++ (autoTools pkgs)
                  ++ (buildDeps pkgs).buildInputs
                  ++ (buildDeps pkgs).nativeBuildInputs;

              env = {
                rustPlatform,
                pkgs,
                ...
              }:
                {
                  RUST_SRC_PATH = toString rustPlatform.rustLibSrc;
                }
                // (buildDeps pkgs).env;
            };
            miri = {
              packages = pkgs:
                with pkgs;
                  [miriRustToolchain]
                  ++ (config.tools pkgs)
                  ++ (autoTools pkgs)
                  ++ (buildDeps pkgs).buildInputs
                  ++ (buildDeps pkgs).nativeBuildInputs;

              inherit (default) env;
            };
          }
          // (optionalAttrs hasMsrv {
            msrv = {
              packages = pkgs:
                with pkgs;
                  [msrvRustToolchain]
                  ++ (config.tools pkgs)
                  ++ (autoTools pkgs)
                  ++ (buildDeps pkgs).buildInputs
                  ++ (buildDeps pkgs).nativeBuildInputs;

              inherit (devShells.default) env;
            };
          });

        formatters = pkgs:
          with pkgs; {
            "*.nix" = getExe alejandra;
            "*.rs" = getExe rustfmt;
          };
      }
    ];
  }
