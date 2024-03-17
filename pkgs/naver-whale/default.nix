{ lib, stdenv, fetchurl, wrapGAppsHook, makeWrapper
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, dbus
, dpkg
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gnome
, gsettings-desktop-schemas
, gtk3
, libX11
, libXScrnSaver
, libXcomposite
, libXcursor
, libXdamage
, libXext
, libXfixes
, libXi
, libXrandr
, libXrender
, libXtst
, libdrm
, libkrb5
, libuuid
, libxkbcommon
, libxshmfence
, mesa
, nspr
, nss
, pango
, pipewire
, snappy
, udev
, wayland
, xdg-utils
, coreutils
, xorg
, zlib
, commandLineArgs ? ""
, pulseSupport ? stdenv.isLinux
, libpulseaudio
, libGL
, libvaSupport ? stdenv.isLinux
, libva
, enableVideoAcceleration ? libvaSupport
, vulkanSupport ? false
, addOpenGLRunpath
, enableVulkan ? vulkanSupport
}:
let
  inherit (lib) optional optionals makeLibraryPath makeSearchPathOutput makeBinPath
    optionalString strings escapeShellArg;

  version = "3.25.232.19";

  deps = [
    alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus expat
    fontconfig freetype gdk-pixbuf glib gtk3 libdrm libX11 libGL
    libxkbcommon libXScrnSaver libXcomposite libXcursor libXdamage
    libXext libXfixes libXi libXrandr libXrender libxshmfence
    libXtst libuuid mesa nspr nss pango pipewire udev wayland
    xorg.libxcb zlib snappy libkrb5 stdenv.cc.cc
  ]
    ++ optional pulseSupport libpulseaudio
    ++ optional libvaSupport libva;

  rpath = makeLibraryPath deps + ":" + makeSearchPathOutput "lib" "lib64" deps;
  binpath = makeBinPath deps;

  enableFeatures = optionals enableVideoAcceleration [ "VaapiVideoDecoder" "VaapiVideoEncoder" ]
    ++ optional enableVulkan "Vulkan";

  disableFeatures = optional enableVideoAcceleration "UseChromeOSDirectVideoDecoder";
in
stdenv.mkDerivation {
  pname = "naver-whale";
  inherit version;

  src = fetchurl {
    url = "https://repo.whale.naver.com/stable/deb/pool/main/n/naver-whale-stable/naver-whale-stable_${version}-1_amd64.deb";
    sha256 = "sha256-DiEklas+3FaK/TnfaCkTF0CnvQZG6w3i1+9M4OebB0U=";
  };

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  doInstallCheck = true;

  nativeBuildInputs = [
    dpkg
    (wrapGAppsHook.override { inherit makeWrapper; })
  ];

  buildInputs = [
    glib gsettings-desktop-schemas gtk3
    gnome.adwaita-icon-theme
  ];

  unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner";

  installPhase = ''
    runHook preInstall
    mkdir -p $out $out/bin
    cp -R usr/share $out
    cp -R opt/ $out/opt

    export BINARYWRAPPER=$out/opt/naver/whale/naver-whale

    substituteInPlace $BINARYWRAPPER \
          --replace /bin/bash ${stdenv.shell}

    ln -sf $BINARYWRAPPER $out/bin/naver-whale-stable

    for exe in $out/opt/naver/whale/{whale,chrome_crashpad_handler}; do
      patchelf \
        --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        --set-rpath "${rpath}" $exe
    done

    substituteInPlace $out/share/applications/naver-whale.desktop \
          --replace /usr/bin/naver-whale-stable $out/bin/naver-whale-stable
      substituteInPlace $out/share/gnome-control-center/default-apps/naver-whale.xml \
          --replace /opt/naver $out/opt/naver
      substituteInPlace $out/share/menu/naver-whale.menu \
          --replace /opt/naver $out/opt/naver
      substituteInPlace $out/opt/naver/whale/default-app-block \
          --replace /opt/naver $out/opt/naver

    icon_sizes=("16" "24" "32" "48" "64" "128" "256")

    for icon in ''${icon_sizes[*]}
    do
      mkdir -p $out/share/icons/hicolor/$icon\x$icon/apps
      ln -s $out/opt/naver/whale/product_logo_$icon.png $out/share/icons/hicolor/$icon\x$icon/apps/naver-whale.png
    done
    ln -sf ${xdg-utils}/bin/xdg-settings $out/opt/naver/whale/xdg-settings
    ln -sf ${xdg-utils}/bin/xdg-mime $out/opt/naver/whale/xdg-mime

    runHook postInstall
  '';

  preFixup = ''
    # Add command line args to wrapGApp.
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${rpath}
      --prefix PATH : ${binpath}
      --suffix PATH : ${lib.makeBinPath [ xdg-utils coreutils ]}
      ${optionalString (enableFeatures != []) ''
      --add-flags "--enable-features=${strings.concatStringsSep "," enableFeatures}"
      ''}
      ${optionalString (disableFeatures != []) ''
      --add-flags "--disable-features=${strings.concatStringsSep "," disableFeatures}"
      ''}
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"
      ${optionalString vulkanSupport ''
      --prefix XDG_DATA_DIRS  : "${addOpenGLRunpath.driverLink}/share"
      ''}
      --add-flags ${escapeShellArg commandLineArgs}
    )
  '';

  installCheckPhase = ''
    # Bypass upstream wrapper which suppresses errors
    $out/bin/naver-whale-stable --version
  '';

  meta = with lib; {
    description = "The web browser from NAVER";
    homepage = "https://whale.naver.com";
    platforms = [ "x86_64-linux" ];
  };
}
