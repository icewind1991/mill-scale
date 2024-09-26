{ pkgsCross, perl, callPackage, freebsdCross }:
let
  freebsdSysrootX86 = callPackage ./freebsd-sysroot.nix {
    arch = "amd64";
    sha256 = "sha256-/XZXt0bPI9bTXrD+TR2KYzhE7wKpVAvKndWL3tqe5cg=";
    version = freebsdCross.versionData.revision;
  };
in
{
  "armv7-unknown-linux-musleabihf" = {
    targetStdenv = pkgsCross.muslpi.stdenv;
  };
  "armv7-unknown-linux-gnueabihf" = {
    targetStdenv = pkgsCross.armv7l-hf-multiplatform.stdenv;
  };
  "aarch64-unknown-linux-gnu" = {
    targetStdenv = pkgsCross.aarch64-multiplatform.stdenv;
  };
  "aarch64-unknown-linux-musl" = {
    targetStdenv = pkgsCross.aarch64-multiplatform-musl.stdenv;
    cFlags = "-mno-outline-atomics";
  };
  "i686-unknown-linux-musl" = {
    targetStdenv = pkgsCross.musl32.stdenv;
  };
  "i686-unknown-linux-gnu" = {
    targetStdenv = pkgsCross.gnu32.stdenv;
  };
  "x86_64-pc-windows-gnu" = {
    targetStdenv = pkgsCross.mingwW64.stdenv;
    # rink wants perl for windows targets
    buildInputs = [ perl ];
    targetDeps = [ pkgsCross.mingwW64.windows.pthreads ];
    rustFlags = "-C target-feature=+crt-static";
    BINARY_SUFFIX = ".exe";
  };
  "x86_64-unknown-freebsd" = {
    targetStdenv = pkgsCross.x86_64-freebsd.stdenv;
    targetDeps = [ freebsdSysrootX86 ];
    dontPatchELF = true;
    postInstall = ''
      patchelf --set-interpreter /libexec/ld-elf.so.1 $out/bin/*
    '';
    X86_64_UNKNOWN_FREEBSD_OPENSSL_DIR = freebsdSysrootX86;
    BINDGEN_EXTRA_CLANG_ARGS_x86_64_unknown_freebsd = "--sysroot=${freebsdSysrootX86}";
  };
  "x86_64-unknown-linux-musl" = {
    targetStdenv = pkgsCross.musl64.stdenv;
  };
  "x86_64-unknown-linux-gnu" = {
    targetStdenv = pkgsCross.gnu64.stdenv;
  };
}
