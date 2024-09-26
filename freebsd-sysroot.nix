{ stdenv
, fetchzip
, arch
, version
, sha256
,
}:
stdenv.mkDerivation {
  pname = "freebsd-sysroot";
  version = "${version}-${arch}";
  src = fetchzip {
    url = "https://download.freebsd.org/ftp/releases/${arch}/${version}-RELEASE/base.txz";
    stripRoot = false;
    inherit sha256;
  };

  doBuild = false;
  dontFixup = true;
  installPhase = ''
    # adapted from https://github.com/cross-rs/cross/blob/main/docker/freebsd.sh#L184

    ls -l

    mkdir -p $out/lib/
    cp -r "usr/include" "$out"
    cp -r "lib/"* "$out/lib"
    cp "usr/lib/libc++.so" "$out/lib"
    cp "usr/lib/libc++.a" "$out/lib"
    cp "usr/lib/libcxxrt.a" "$out/lib"
    cp "usr/lib/libcompiler_rt.a" "$out/lib"
    cp "usr/lib"/lib{c,util,m,ssp_nonshared,memstat}.a "$out/lib"
    cp "usr/lib/librt.so" "$out/lib"
    cp "usr/lib"/lib{execinfo,procstat}.so.1 "$out/lib"
    cp "usr/lib"/libmemstat.so.3 "$out/lib"
    cp "usr/lib"/{crt1,Scrt1,crti,crtn}.o "$out/lib"
    cp "usr/lib"/libkvm.a "$out/lib"

    local lib=
    local base=
    local link=
    for lib in "''${out}/lib/"*.so.*; do
        base=$(basename "''${lib}")
        link="''${base}"
        # not strictly necessary since this will always work, but good fallback
        while [[ "''${link}" == *.so.* ]]; do
            link="''${link%.*}"
        done

        # just extra insurance that we won't try to overwrite an existing file
        local dstlink="''${out}/lib/''${link}"
        if [[ -n "''${link}" ]] && [[ "''${link}" != "''${base}" ]] && [[ ! -f "''${dstlink}" ]]; then
            ln -s "''${base}" "''${dstlink}"
        fi
    done

    ln -s libthr.so.3 "''${out}/lib/libpthread.so"
  '';
}
