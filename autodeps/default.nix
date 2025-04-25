{
  lib,
  src,
  config,
}: let
  inherit (builtins) readFile pathExists attrNames hasAttr;
  inherit (lib) map intersectLists foldl splitString getAttrFromPath;

  cargoLockDeps =
    if pathExists (src + /Cargo.lock)
    then let
      cargoLock = fromTOML (readFile (src + /Cargo.lock));
    in
      map (package: package.name) cargoLock.package
    else [];
  availableAutoDeps = import ./deps.nix;
  detectedDeps = intersectLists cargoLockDeps (attrNames availableAutoDeps);
  mergedDetectedDeps =
    if config.autodeps
    then
      foldl
      (merged: dep: {
        build = merged.build ++ (availableAutoDeps.${dep}.build or []);
        native = merged.native ++ (availableAutoDeps.${dep}.native or []);
        runtime = merged.runtime ++ (availableAutoDeps.${dep}.runtime or []);
        env =
          if (hasAttr "env" availableAutoDeps.${dep})
          then pkgs: (merged.env pkgs) // (availableAutoDeps.${dep}.env pkgs)
          else merged.env;
      })
      {
        build = [];
        native = [];
        runtime = [];
        env = pkgs: {};
      }
      detectedDeps
    else {
      build = [];
      native = [];
      runtime = [];
      env = pkgs: {};
    };
  getPkgs = pkgs: deps: let
    depPaths = map (splitString ".") deps;
  in
    map (path: getAttrFromPath path pkgs) depPaths;
  autoDeps = pkgs: {
    buildInputs = getPkgs pkgs (lib.traceValSeq mergedDetectedDeps.build);
    nativeBuildInputs = with pkgs; [pkg-config] ++ (getPkgs pkgs mergedDetectedDeps.native);
    runtimeInputs = getPkgs pkgs mergedDetectedDeps.runtime;
    env = mergedDetectedDeps.env pkgs;
  };
in
  autoDeps
