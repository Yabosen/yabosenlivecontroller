#!/bin/sh
# Yabosen Controller installer for Linux (x86_64).
#
#   curl -fsSL https://github.com/Yabosen/yabosenlivecontroller/releases/latest/download/install.sh | sh
#
# Picks the right package for your distro: .deb (Debian/Ubuntu/Mint/Pop), .rpm
# (Fedora/RHEL/openSUSE), .pkg.tar.zst (Arch/Manjaro/EndeavourOS), or an AppImage
# in ~/.local/bin for anything else. Options (after `sh -s --`):
#   --appimage        install the AppImage for your user only (no root needed)
#   --version vX.Y.Z  install a specific release instead of the latest
#   --uninstall       remove it again
set -eu

REPO="Yabosen/yabosenlivecontroller"
APP="yabosen-controller"
NAME="Yabosen Controller"

say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

usage() {
	cat <<EOF
Installs $NAME on Linux (x86_64).

  curl -fsSL https://github.com/$REPO/releases/latest/download/install.sh | sh -s -- [options]

Options:
  --appimage        install the AppImage for your user only (no root needed)
  --version vX.Y.Z  install a specific release instead of the latest
  --uninstall       remove it again
EOF
}

as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif has sudo; then
		sudo "$@"
	elif has doas; then
		doas "$@"
	else
		die "root is needed to install a system package (no sudo/doas found). Re-run with --appimage to install for your user only."
	fi
}

fetch() { # url dest
	if has curl; then
		curl -fL --retry 3 --progress-bar -o "$2" "$1"
	elif has wget; then
		wget -q --show-progress -O "$2" "$1"
	else
		die "curl or wget is required"
	fi
}

# Which kind of package fits this system.
detect_format() {
	if has pacman; then
		echo arch
	elif has apt-get && has dpkg; then
		echo deb
	elif has dnf || has yum || has zypper; then
		echo rpm
	else
		echo appimage
	fi
}

asset_for() {
	case $1 in
	deb) echo "$APP-amd64.deb" ;;
	rpm) echo "$APP-x86_64.rpm" ;;
	arch) echo "$APP-x86_64.pkg.tar.zst" ;;
	appimage) echo "$APP-x86_64.AppImage" ;;
	esac
}

user_bin="${XDG_BIN_HOME:-$HOME/.local/bin}"
user_data="${XDG_DATA_HOME:-$HOME/.local/share}"

install_appimage() { # dir-with-downloads
	mkdir -p "$user_bin" "$user_data/applications" "$user_data/icons/hicolor/256x256/apps"
	install -m 755 "$1/$(asset_for appimage)" "$user_bin/$APP.AppImage"
	ln -sf "$user_bin/$APP.AppImage" "$user_bin/$APP"
	fetch "$base/$APP.png" "$user_data/icons/hicolor/256x256/apps/$APP.png"
	cat >"$user_data/applications/$APP.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NAME
Comment=Control your live status on yabosen.live
Exec=$user_bin/$APP.AppImage
Icon=$APP
Terminal=false
Categories=Utility;Network;
StartupWMClass=$APP
EOF
	has update-desktop-database && update-desktop-database "$user_data/applications" >/dev/null 2>&1 || true
	if ! has fusermount && ! has fusermount3; then
		warn "AppImages need FUSE. If it won't start, install fuse (e.g. 'fuse3' or 'libfuse2') or run it with --appimage-extract-and-run."
	fi
	case ":$PATH:" in
	*":$user_bin:"*) ;;
	*) warn "$user_bin is not on your PATH; start it from your app menu or add it to PATH." ;;
	esac
}

install_package() { # format file
	case $1 in
	deb) as_root apt-get install -y "$2" ;;
	arch) as_root pacman -U --noconfirm --needed "$2" ;;
	rpm)
		if has dnf; then
			as_root dnf install -y "$2"
		elif has zypper; then
			as_root zypper --non-interactive install --allow-unsigned-rpm "$2"
		else
			as_root yum install -y "$2"
		fi
		;;
	esac
}

uninstall() {
	removed=false
	if has dpkg && dpkg -s "$APP" >/dev/null 2>&1; then
		as_root apt-get remove -y "$APP" && removed=true
	fi
	if has pacman && pacman -Q "$APP" >/dev/null 2>&1; then
		as_root pacman -R --noconfirm "$APP" && removed=true
	fi
	if has rpm && rpm -q "$APP" >/dev/null 2>&1; then
		if has dnf; then
			as_root dnf remove -y "$APP"
		elif has zypper; then
			as_root zypper --non-interactive remove "$APP"
		else
			as_root yum remove -y "$APP"
		fi
		removed=true
	fi
	if [ -e "$user_bin/$APP.AppImage" ]; then
		rm -f "$user_bin/$APP.AppImage" "$user_bin/$APP" \
			"$user_data/applications/$APP.desktop" \
			"$user_data/icons/hicolor/256x256/apps/$APP.png"
		removed=true
	fi
	# Created by the app's "Start when I log in" option.
	rm -f "$HOME/.config/autostart/$NAME.desktop"
	if $removed; then
		say "$NAME removed. Your settings are kept in ~/.config/yabosencontroller."
	else
		say "$NAME doesn't seem to be installed."
	fi
}

# ---------------------------------------------------------------------------

format=""
version=""
action=install
while [ $# -gt 0 ]; do
	case $1 in
	--appimage) format=appimage ;;
	--version)
		[ $# -ge 2 ] || die "--version needs a value, e.g. --version v1.0.0"
		version=$2
		shift
		;;
	--uninstall) action=uninstall ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1 (try --help)" ;;
	esac
	shift
done

[ "$(uname -s)" = Linux ] || die "this installer is for Linux. On Windows, use install.ps1."

if [ "$action" = uninstall ]; then
	uninstall
	exit 0
fi

[ "$(uname -m)" = x86_64 ] || die "only x86_64 builds are available (this machine is $(uname -m))."

if [ -n "$version" ]; then
	base="https://github.com/$REPO/releases/download/$version"
else
	base="https://github.com/$REPO/releases/latest/download"
fi
[ -n "$format" ] || format=$(detect_format)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM
chmod 755 "$tmp" # package managers (e.g. apt's _apt user) must be able to read it

asset=$(asset_for "$format")
say "Downloading $asset"
fetch "$base/$asset" "$tmp/$asset"

if [ "$format" = appimage ]; then
	say "Installing the AppImage for $(id -un)"
	install_appimage "$tmp"
	installed="$user_bin/$APP.AppImage"
else
	say "Installing the $format package (you may be asked for your password)"
	install_package "$format" "$tmp/$asset"
	installed="$(command -v "$APP" || echo "/usr/bin/$APP")"
fi

say "Installed $("$installed" --version 2>/dev/null || echo "$NAME")"
say "Open \"$NAME\" from your app menu, or run: $APP"
