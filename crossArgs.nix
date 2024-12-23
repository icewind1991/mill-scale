{
  callPackage,
  pkgsCross,
  stdenv,
  lib,
}: let
  inherit (lib) hasInfix replaceStrings toUpper concatStrings;
  isMusl = hasInfix "-musl";
  crossOpts = callPackage ./crossOpts.nix {};

  buildCrossArgs = target: {
    targetDeps ? [],
    rustFlags ? (
      if isMusl target
      then "-C target-feature=+crt-static"
      else ""
    ),
    cFlags ? "",
    targetStdenv,
    ...
  } @ args: let
    isHostTarget = targetStdenv.targetPlatform.config == stdenv.targetPlatform.config;
    # don't use the pkgsCross cc if the target is the host platform
    targetCc =
      if isHostTarget
      then stdenv.cc
      else targetStdenv.cc;
    targetUnderscore = replaceStrings ["-"] ["_"] target;
    targetUpperCase = toUpper targetUnderscore;
    rest = removeAttrs args ["rustFlags" "cc" "cFlags" "targetDeps" "targetStdenv" "nativeBuildInputs"];
    # by adding the dependency in the (target specific) linker args instead of buildInputs
    # we can prevent it trying to link to it for host build dependencies
    rustFlagsWithDeps = rustFlags + concatStrings (map (targetDep: " -Clink-arg=-L${targetDep}/lib") targetDeps);
  in (
    {
      nativeBuildInputs = (args.nativeBuildInputs or []) ++ [targetCc stdenv.cc];
      "CARGO_TARGET_${targetUpperCase}_RUSTFLAGS" = rustFlagsWithDeps;
      "CARGO_TARGET_${targetUpperCase}_LINKER" = "${targetCc.targetPrefix}cc";
      "AR_${targetUnderscore}" = "${targetCc.targetPrefix}ar";
      "CC_${targetUnderscore}" = "${targetCc.targetPrefix}cc";
      "CCX_${targetUnderscore}" = "${targetCc.targetPrefix}ccx";
      "HOST_CC" = "${stdenv.cc.targetPrefix}cc";
      "CFLAGS_${targetUnderscore}" = cFlags;
    }
    // rest
  );
in
  target: buildCrossArgs target crossOpts.${target}
