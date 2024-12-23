# mill-scale -- Another rust module for flakelight
# Copyright (C) 2024 Robin Appelman <robin@icewind.nl>
# SPDX-License-Identifier: MIT
{
  description = "Another rust module for flakelite";
  inputs = {
    flakelight.url = "github:nix-community/flakelight";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "flakelight/nixpkgs";
    };
  };
  outputs = {
    flakelight,
    crane,
    rust-overlay,
    ...
  }:
    flakelight ./. {
      imports = [flakelight.flakelightModules.flakelightModule];
      formatters = pkgs:
        with pkgs; {
          "*.nix" = pkgs.lib.getExe alejandra;
        };
      flakelightModule = {lib, ...}: {
        imports = [./mill-scale.nix];
        inputs.crane = lib.mkDefault crane;
        inputs.rust-overlay = lib.mkDefault rust-overlay;
      };
    };
}
