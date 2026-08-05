{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  # https://devenv.sh/basics/
  env = {
    GREET = "devenv";

    KO_HOME = "${config.env.DEVENV_STATE}/koreader-home";
    KOREADER_SRC = "${config.env.DEVENV_STATE}/koreader-src";
    KOREADER_REPO = "https://github.com/koreader/koreader.git";
    KOREADER_REF = "master";

    CC = "ccache gcc";
    CXX = "ccache g++";
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      pkgs.SDL2
      pkgs.libGL
      pkgs.libglvnd
      pkgs.wayland
      pkgs.libxkbcommon
      pkgs.xorg.libX11
      pkgs.xorg.libXext
      pkgs.xorg.libXcursor
      pkgs.xorg.libXrandr
      pkgs.xorg.libXi
      pkgs.xorg.libXfixes
    ];
  };

  # https://devenv.sh/packages/
  packages = with pkgs; [
    nodejs_24
    prettier
    luajitPackages.busted

    # KOReader build system
    cmake
    ninja
    gnumake
    meson
    autoconf
    automake
    libtool
    patch

    # Compilers
    gcc
    gpp
    clang

    # KOReader build utilities
    git
    pkg-config
    gettext
    perl
    bash
    coreutils
    findutils
    gzip
    unzip
    wget
    curl
    binutils
    nasm

    # Emulator runtime (built-in SDL needs these headers at configure time)
    SDL2
    libGL
    libglvnd
    dbus
    libxkbcommon
    wayland
    wayland-protocols
    wayland-scanner
    libdecor
    xorg.libX11
    xorg.libxcb
    xorg.libXcursor
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXScrnSaver
    xorg.libXtst

    # Optional / nice-to-have
    ccache
    shellcheck
    shfmt
    p7zip
  ];

  languages.c.enable = true;
  languages.lua.enable = true;
  languages.python.enable = true;

  processes = {
    docs.exec = "cd docs; npx docusaurus start";
  };

  # https://devenv.sh/scripts/
  scripts.hello.exec = ''
    echo hello from $GREET
  '';

  scripts.koreader-link-plugins.exec = ''
    set -euo pipefail

    mkdir -p "$KO_HOME/plugins"

    PLUGIN_DST="$KO_HOME/plugins/comicreader.koplugin"
    if [ -L "$PLUGIN_DST" ]; then
      rm "$PLUGIN_DST"
    fi
    mkdir -p "$PLUGIN_DST"

    for entry in main.lua _meta.lua src version.txt LICENSE.md README.md CHANGELOG.md; do
      SRC_ENTRY="$DEVENV_ROOT/$entry"
      DST_ENTRY="$PLUGIN_DST/$entry"
      if [ ! -e "$SRC_ENTRY" ]; then
        continue
      fi
      if [ -L "$DST_ENTRY" ] || [ -e "$DST_ENTRY" ]; then
        rm -rf "$DST_ENTRY"
      fi
      ln -s "$SRC_ENTRY" "$DST_ENTRY"
    done
    echo "✓ Linked comicreader.koplugin into $PLUGIN_DST"

    # Patched statistics overrides the built-in plugin in the KOReader source tree.
    STATS_SRC="$DEVENV_ROOT/extra-plugins/statistics.koplugin"
    if [ ! -f "$STATS_SRC/main.lua" ]; then
      echo "→ Initializing statistics.koplugin submodule..."
      git -C "$DEVENV_ROOT" submodule update --init --recursive extra-plugins/statistics.koplugin
    fi

    if [ -d "$KOREADER_SRC/plugins" ] && [ -f "$STATS_SRC/main.lua" ]; then
      STATS_DST="$KOREADER_SRC/plugins/statistics.koplugin"
      if [ -L "$STATS_DST" ]; then
        if [ "$(readlink "$STATS_DST")" != "$STATS_SRC" ]; then
          rm "$STATS_DST"
          ln -s "$STATS_SRC" "$STATS_DST"
          echo "✓ Relinked statistics.koplugin override"
        else
          echo "✓ statistics.koplugin already linked"
        fi
      else
        rm -rf "$STATS_DST"
        ln -s "$STATS_SRC" "$STATS_DST"
        echo "✓ Linked statistics.koplugin override"
      fi
    fi
  '';

  scripts.koreader-setup.exec = ''
    set -euo pipefail

    REPO="''${KOREADER_REPO:-https://github.com/koreader/koreader.git}"
    REF="''${KOREADER_REF:-master}"

    if command -v ccache >/dev/null 2>&1; then
      ccache --max-size=5G >/dev/null
      ccache --set-config=compression=true >/dev/null || true
    fi

    if [ ! -d "$KOREADER_SRC/.git" ]; then
      echo "→ Cloning KOReader ($REPO @ $REF) into $KOREADER_SRC"
      mkdir -p "$(dirname "$KOREADER_SRC")"
      git clone --recursive "$REPO" "$KOREADER_SRC"
    fi

    echo "→ Checking out $REF"
    git -C "$KOREADER_SRC" fetch --tags origin
    git -C "$KOREADER_SRC" checkout "$REF"
    git -C "$KOREADER_SRC" submodule update --init --recursive

    koreader-link-plugins

    echo "→ Fetching third-party dependencies"
    (cd "$KOREADER_SRC" && ./kodev fetch-thirdparty)

    echo "→ Building emulator"
    (cd "$KOREADER_SRC" && ./kodev build)

    echo "✓ KOReader emulator ready at $KOREADER_SRC"
  '';

  scripts.koreader-run.exec = ''
    set -euo pipefail

    koreader-link-plugins

    EMULATOR_DIR=$(find "$KOREADER_SRC" -maxdepth 1 -type d -name 'koreader-emulator-*' 2>/dev/null | head -1 || true)
    if [ ! -d "$KOREADER_SRC/.git" ] || [ -z "''${EMULATOR_DIR}" ]; then
      echo "→ KOReader not built yet; running koreader-setup first..."
      koreader-setup
    fi

    cd "$KOREADER_SRC"
    exec ./kodev run "$@"
  '';

  enterShell = ''
    hello
    koreader-link-plugins || true
    echo "KOReader: koreader-setup | koreader-run"
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    git --version | grep --color=auto "${pkgs.git.version}"
  '';

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
    yamllint.enable = true;
    prettier.enable = true;
  };

  # See full reference at https://devenv.sh/reference/options/
}
