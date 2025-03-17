{
  "openssl-sys" = {
    build = ["openssl"];
    env = pkgs: {OPENSSL_NO_VENDOR = "1";};
  };
  "libudev-sys" = {build = ["eudev"];};
  "libdbus-sys" = {build = ["dbus"];};
  "expat-sys" = {native = ["cmake"];};
  "servo-fontconfig-sys" = {build = ["fontconfig"];};
  "x11-dl" = {build = ["xorg.libX11" "xorg.libXcursor" "xorg.libXrandr" "xorg.libXi"];};
  "glutin_glx_sys" = {runtime = ["libGL" "libGLU"];};
  "wayland-egl" = {build = ["egl-wayland"];};
  "wayland-sys" = {runtime = ["wayland" "libxkbcommon"];};
  "libsodium-sys" = {build = ["libsodium"];};
}
