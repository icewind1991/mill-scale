# Mill Scale

An opinionated rust module for [flakelight](https://github.com/nix-community/flakelight).

## Features

Included checks:

- Verify MSRV (if specified in `Cargo.toml`)
- Test and clippy with default features
- Test and clippy with all features (if features are defined)
- Test and clippy with no default features (if default features are defined)

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    flakelight = {
      url = "github:nix-community/flakelight";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mill-scale = {
      url = "github:icewind1991/mill-scale";
      inputs.flakelight.follows = "flakelight";
    };
  };
  outputs = { mill-scale, ... }: mill-scale ./. {};
}
```

## Usage with GitHub Actions

### Single runner

```yaml
name: "CI"
on:
  pull_request:
  push:

jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v26
        # insert cache setup here
      - run: nix flake check --keep-going
```

### Split over multiple runners

This automatically creates one job per check, allowing them to run in parallel.

This might be slower than running them all in the same runner depending on the time each check takes and the size of the intermediates that has to be downloaded from the cache.

```yaml
name: "CI"
on:
  pull_request:
  push:

jobs:
  matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - id: set-matrix
        run: echo "matrix={\"check\":$(nix eval --json '.#checks.x86_64-linux' --apply 'builtins.attrNames')}" | tee $GITHUB_OUTPUT

  checks:
    runs-on: ubuntu-latest
    needs: [matrix]
    strategy:
      fail-fast: false
      matrix: ${{fromJson(needs.matrix.outputs.matrix)}}
    name: ${{ matrix.check }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v26
        # insert cache setup here
      - run: nix build .#checks.x86_64-linux.${{ matrix.check }}
```

## Credits

This flake is based on [flakelight-rust](https://github.com/accelbread/flakelight-rust), credit for most ideas got to accelbread.
