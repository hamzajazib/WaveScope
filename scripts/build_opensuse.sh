#!/usr/bin/env bash
# build_opensuse.sh — Build an openSUSE .rpm package for WaveScope
# Usage: ./scripts/build_opensuse.sh [version]
# Example: ./scripts/build_opensuse.sh 1.3.1
#
# Requires: rpm-build
#   openSUSE: sudo zypper install -y rpm-build
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-$(grep -m1 'VERSION' "$REPO_ROOT/wavescope_app/core_base.py" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')}"
PKGNAME="wavescope"
RPM_BUILD_DIR="$REPO_ROOT/_rpm_build_opensuse"
TARBALL_NAME="${PKGNAME}-${VERSION}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building WaveScope v${VERSION}  →  openSUSE .rpm"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Cleanup and scaffold
rm -rf "$RPM_BUILD_DIR"
mkdir -p \
    "$RPM_BUILD_DIR/SPECS" \
    "$RPM_BUILD_DIR/SOURCES" \
    "$RPM_BUILD_DIR/BUILD" \
    "$RPM_BUILD_DIR/RPMS" \
    "$RPM_BUILD_DIR/SRPMS"

# 2. Create source tarball
STAGING="$RPM_BUILD_DIR/$TARBALL_NAME"
mkdir -p "$STAGING/assets"
cp "$REPO_ROOT/main.py" "$REPO_ROOT/requirements.txt" "$STAGING/"
cp -r "$REPO_ROOT/wavescope_app" "$STAGING/"
cp -r "$REPO_ROOT/assets/." "$STAGING/assets/"
tar -czf "$RPM_BUILD_DIR/SOURCES/${TARBALL_NAME}.tar.gz" \
    -C "$RPM_BUILD_DIR" "$TARBALL_NAME"

# 3. Write openSUSE spec file
cat > "$RPM_BUILD_DIR/SPECS/${PKGNAME}.spec" <<SPEC
Name:           ${PKGNAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Modern WiFi Analyzer for Linux
License:        MIT
URL:            https://github.com/yurividal/WaveScope
Source0:        ${TARBALL_NAME}.tar.gz
BuildArch:      noarch

# Runtime dependencies (openSUSE names)
Requires:       python3 >= 3.10
Requires:       python3-pip
Requires:       python3-qt6
Requires:       NetworkManager
Requires:       iw
Requires:       tcpdump
Requires:       polkit
Requires:       libxcb-cursor0
Requires:       libgthread-2_0-0

%description
WaveScope is a fast, modern WiFi analyzer for Linux built with PyQt6.
It displays real-time channel occupancy graphs, signal history,
per-AP metadata (security, WiFi generation, OUI manufacturer,
channel utilization, k/v/r roaming support) and supports both
dark and light themes.

Requires NetworkManager (nmcli) and iw for full functionality.

%prep
%autosetup -n ${TARBALL_NAME}

%install
install -dm 755 %{buildroot}/opt/wavescope
install -pm 644 main.py requirements.txt %{buildroot}/opt/wavescope/
cp -r wavescope_app %{buildroot}/opt/wavescope/
cp -r assets %{buildroot}/opt/wavescope/

install -dm 755 %{buildroot}/usr/bin
install -dm 755 %{buildroot}/usr/share/applications
install -dm 755 %{buildroot}/usr/share/icons/hicolor/scalable/apps

cat > %{buildroot}/usr/bin/wavescope <<'LAUNCHER'
#!/usr/bin/env bash
exec /opt/wavescope/.venv/bin/python /opt/wavescope/main.py "\$@"
LAUNCHER
chmod 0755 %{buildroot}/usr/bin/wavescope

cat > %{buildroot}/usr/share/applications/wavescope.desktop <<'DESKTOP'
[Desktop Entry]
Name=WaveScope
Comment=Modern WiFi Analyzer for Linux
Exec=wavescope
Icon=wavescope
Terminal=false
Type=Application
Categories=Network;Utility;
Keywords=wifi;wireless;network;analyzer;
StartupWMClass=wavescope
DESKTOP

install -pm 644 assets/icon.svg \
    %{buildroot}/usr/share/icons/hicolor/scalable/apps/wavescope.svg

%post
set -e
VENV="/opt/wavescope/.venv"
echo "Setting up Python environment for WaveScope..."
rm -rf "\$VENV"
python3 -m venv --system-site-packages "\$VENV"
"\$VENV/bin/pip" install --upgrade pip -q
"\$VENV/bin/pip" install --quiet \
    "pyqtgraph>=0.13.0" \
    "numpy>=1.23.0"
echo "WaveScope ready. Run: wavescope"

%preun
if [ \$1 -eq 0 ]; then
    rm -rf /opt/wavescope/.venv
fi

%files
/opt/wavescope/main.py
/opt/wavescope/requirements.txt
/opt/wavescope/wavescope_app/
/opt/wavescope/assets/
/usr/bin/wavescope
/usr/share/applications/wavescope.desktop
/usr/share/icons/hicolor/scalable/apps/wavescope.svg

%changelog
* $(date "+%a %b %d %Y") WaveScope Contributors <https://github.com/yurividal/WaveScope> - ${VERSION}-1
- See https://github.com/yurividal/WaveScope/releases for full changelog
SPEC

# 4. Build RPM
rpmbuild --define "_topdir $RPM_BUILD_DIR" \
         -bb "$RPM_BUILD_DIR/SPECS/${PKGNAME}.spec"

# 5. Copy output to project root
RPM_FILE=$(find "$RPM_BUILD_DIR/RPMS" -name "*.rpm" | head -1)
if [[ -n "$RPM_FILE" ]]; then
    cp "$RPM_FILE" "$REPO_ROOT/"
    RPM_BASENAME="$(basename "$RPM_FILE")"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Built: $RPM_BASENAME"
    echo ""
    echo "  Install:  sudo zypper install ./$RPM_BASENAME"
    echo "  Run:      wavescope"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Cleanup
rm -rf "$RPM_BUILD_DIR"
