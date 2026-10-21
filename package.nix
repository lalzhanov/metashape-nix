{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  glibc,
  gcc,
  glib,
  gmp,
  gomp,
  expat,
  freetype,
  libGL,
  libGLU,
  curl,
  libkrb5,
  gtk2,
  fontconfig,
  libxkbcommon,
  libxcb,
  libx11,
  libsm,
  libice,
  libxcb-wm,
  libxcb-image,
  libxcb-keysyms,
  libxcb-render-util,
  libdrm,
  libxshmfence,
  zlib,
  bzip2,
  xz,
  libnsl,
  sqlite,
  libXft,
  libxscrnsaver,
  libxcrypt-legacy,
  gst_all_1,
  qt5,
  udev,
  unixodbc,
  onnxruntime,
  renderdoc,
  ocl-icd,
  vulkan-loader,
  pro ? false,
  ...
}:

let
  pin = builtins.fromJSON (builtins.readFile ./pin.json);
  version = lib.concatStringsSep "." (map toString pin.version);
  linkVersion = lib.concatStringsSep "_" (map toString pin.version);
  pname = if pro then "metashape-pro" else "metashape";
  desktopName = if pro then "Agisoft Metashape Professional" else "Agisoft Metashape";

  src = fetchurl (
    if pro then
      {
        url = "https://download.agisoft.com/metashape-pro_${linkVersion}_amd64.tar.gz";
        sha256 = pin.proHash;
      }
    else
      {
        url = "https://download.agisoft.com/metashape_${linkVersion}_amd64.tar.gz";
        sha256 = pin.standardHash;
      }
  );

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = desktopName;
    exec = pname;
    icon = pname;
    comment = "Surface reconstruction from photos";
    categories = [ "Science" ];
    startupWMClass = if pro then "Metashape Pro" else "Metashape";
  };

  gstPlugins = [
    gst_all_1.gstreamer.out
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
  ];

  onnxruntimeShim = stdenv.mkDerivation {
    pname = "metashape-onnxruntime-shim";
    version = "1.18.1";
    dontUnpack = true;

    buildPhase = ''
      cat > shim.c <<'EOF'
      #include <dlfcn.h>

      void *OrtGetApiBase(void)
      {
        typedef void *(*fn_t)(void);
        static fn_t fn;

        if (!fn) {
          void *handle = dlopen("${onnxruntime}/lib/libonnxruntime.so.1", RTLD_NOW | RTLD_GLOBAL);
          if (!handle)
            return 0;
          fn = (fn_t)dlsym(handle, "OrtGetApiBase");
        }

        return fn ? fn() : 0;
      }
      EOF
      cat > shim.map <<'EOF'
      VERS_1.18.1 {
        global: OrtGetApiBase;
        local: *;
      };
      EOF
      $CC -shared -fPIC -o libonnxruntime.so.1.18.1 shim.c -ldl \
        -Wl,-soname,libonnxruntime.so.1.18.1 \
        -Wl,--version-script=shim.map
    '';

    installPhase = ''
      install -Dm755 libonnxruntime.so.1.18.1 $out/lib/libonnxruntime.so.1.18.1
    '';
  };

  runtimeLibs = [
    libGL
    libGLU
    ocl-icd
    vulkan-loader
    onnxruntime
    renderdoc
  ]
  ++ gstPlugins
  ++ lib.optionals pro [
    udev
    unixodbc
  ];
in
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    desktopItem
    ;

  sourceRoot = if pro then "metashape-pro" else "metashape";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    glibc
    gcc.cc.lib
    glib
    gmp
    gomp
    expat
    freetype
    libGL
    libGLU
    curl
    libkrb5
    gtk2
    fontconfig
    libxkbcommon
    libxcb
    libx11
    libsm
    libice
    libxcb-wm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libdrm
    libxshmfence
    zlib
  ]
  ++ gstPlugins
  ++ lib.optionals pro [
    bzip2
    xz
    libnsl
    sqlite
    libXft
    libxscrnsaver
    libxcrypt-legacy
    qt5.qtbase
    qt5.qtsvg
    qt5.qtremoteobjects
    qt5.qtx11extras
    qt5.qtxmlpatterns
    qt5.qttools
    qt5.qtmultimedia
    qt5.qtserialport
  ];

  dontWrapQtApps = true;

  autoPatchelfIgnoreMissingDeps = lib.optionals pro [ "libclang-8.so.1" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r . $out/
    chmod +x $out/metashape

    mkdir -p $out/bin
    ln -s $out/metashape $out/bin/$pname

    runHook postInstall
  '';

  postFixup = ''
    ln -sf ${onnxruntimeShim}/lib/libonnxruntime.so.1.18.1 $out/lib/libonnxruntime.so.1.18.1
    ln -sf ${onnxruntime}/lib/libonnxruntime_providers_*.so $out/lib/

    wrapProgram $out/metashape \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib" \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}" \
      --set GST_PLUGIN_FEATURE_RANK "pulsesink:NONE"
    ln -sf $out/metashape $out/bin/$pname
  '';

  postInstall = ''
    install -Dm444 ${desktopItem}/share/applications/*.desktop -t $out/share/applications
    install -Dm444 metashape.png $out/share/icons/hicolor/128x128/apps/$pname.png
  '';

  passthru = {
    desktopItems = [ desktopItem ];
  };

  meta = {
    description = "Professional photogrammetry software by Agisoft";
    homepage = "https://www.agisoft.com/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
