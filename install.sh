#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/gr8distance/area51.git"
BUILD_DIR="${TMPDIR:-/tmp}/area51-build"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# --- Check requirements ---

if ! command -v sbcl >/dev/null 2>&1; then
  echo "error: SBCL is required but not found."
  echo ""
  echo "Install SBCL:"
  echo "  macOS:  brew install sbcl"
  echo "  Ubuntu: sudo apt install sbcl"
  echo "  Arch:   sudo pacman -S sbcl"
  echo "  Other:  http://www.sbcl.org/getting.html"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required but not found."
  exit 1
fi

# --- Clone and build ---

echo "Cloning area51..."
rm -rf "$BUILD_DIR"
git clone --depth 1 "$REPO" "$BUILD_DIR"

echo "Building..."
cd "$BUILD_DIR"
sbcl --noinform --non-interactive --load build.lisp

# --- Install ---

if [ -w "$INSTALL_DIR" ]; then
  cp bin/area51 "$INSTALL_DIR/area51"
else
  echo "Installing to $INSTALL_DIR (requires sudo)..."
  sudo cp bin/area51 "$INSTALL_DIR/area51"
fi

# --- Cleanup ---

rm -rf "$BUILD_DIR"

echo ""
echo "area51 installed to $INSTALL_DIR/area51"
echo ""
echo "Get started:"
echo "  area51 new my-app"
echo "  cd my-app"
echo "  area51 add alexandria"
echo "  area51 install"
echo "  area51 run"
