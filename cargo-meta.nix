{lib}: let
  inherit (builtins) isAttrs attrNames;
  inherit (lib) assertMsg remove;
in
  cargoToml: rec {
    tomlPackage = cargoToml.package or cargoToml.workspace.package;
    hasMsrv = tomlPackage ? rust-version;
    hasWorkspace = tomlPackage ? workspace;
    hasFeatures = cargoToml ? features && isAttrs cargoToml.features;
    features = cargoToml.features or {};
    defaultFeatures = features.default or [];
    nonDefaultFeatures = remove "default" (attrNames features);
    hasNonDefaultFeatures = hasFeatures && (defaultFeatures != nonDefaultFeatures);
    hasDefaultFeatures = cargoToml ? features && cargoToml.features ? default;
    msrv = assert assertMsg hasMsrv ''"rust-version" not set in Cargo.toml''; tomlPackage.rust-version;
    dependencies = attrNames (cargoToml.dependencies or {});
    dev-dependencies = attrNames (cargoToml.dev-dependencies or {});
  }
