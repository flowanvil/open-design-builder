#!/usr/bin/env bash
# Install the Open Design Linux AppImage into the desktop application menu.
# Place this script next to open-design-<version>-linux-x64.AppImage and run it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
appimage="$(find "$here" -maxdepth 1 -name 'open-design-*-linux-x64.AppImage' -type f | head -n 1)"
if [ -z "$appimage" ]; then
  echo "No open-design-*-linux-x64.AppImage found next to this script." >&2
  exit 1
fi
appimage="$(readlink -f "$appimage")"

bin_dir="$HOME/.local/bin"
apps_dir="$HOME/.local/share/applications"
mkdir -p "$bin_dir" "$apps_dir"
install -m 755 "$appimage" "$bin_dir/open-design.AppImage"

# The desktop session does not inherit a shell environment: launching the
# AppImage without --appimage-extract-and-run needs FUSE (often unavailable or
# too slow) and ELECTRON_RUN_AS_NODE may leak in from the session. This matches
# the Exec line used by upstream's own installPackedLinuxApp.
desktop="$apps_dir/open-design.desktop"
cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Open Design
GenericName=Open Design
Comment=Local-first design product
Exec=env -u ELECTRON_RUN_AS_NODE $bin_dir/open-design.AppImage --appimage-extract-and-run %U
Icon=open-design
Categories=Development;Utility;
StartupWMClass=Open Design
StartupNotify=true
Terminal=false
MimeType=x-scheme-handler/od;
EOF

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps_dir" 2>/dev/null || true
fi

echo "Installed $desktop"
echo "Open Design is now available from the application menu."
