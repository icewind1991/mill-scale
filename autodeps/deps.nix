{
  "openssl-sys" = { build = [ "openssl" ]; };
  "libudev-sys" = { build = [ "eudev" ]; };
  "libdbus-sys" = { build = [ "dbus" ]; };
  "expat-sys" = { native = [ "cmake" ]; };
  "servo-fontconfig-sys" = { build = [ "fontconfig" ]; };
  "x11-dl" = { build = [ "xorg.libX11" "xorg.libXcursor" "xorg.libXrandr" "xorg.libXi" ]; };
  "glutin_glx_sys" = {
    build = [ "libGL" ];
    env = pkgs: {
      LD_LIBRARY_PATH = with pkgs; "/run/opengl-driver/lib/:${lib.makeLibraryPath ([libGL libGLU])}";
    };
  };
  "wayland-egl" = { build = [ "egl-wayland" ]; };
}
