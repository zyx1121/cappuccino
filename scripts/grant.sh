#!/usr/bin/env bash
# grant.sh — install ONLY the passwordless grant that lets Cappuccino toggle lid-close sleep
# without a prompt. Self-contained: works from a clone OR from inside the app bundle
# (Contents/Resources), so cask users can run it after install.
#
# It writes one tightly-scoped sudoers drop-in (root:wheel, 0440) permitting exactly two
# commands and nothing else. Undo: `sudo rm /etc/sudoers.d/cappuccino-disablesleep`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDOERS_DST="/etc/sudoers.d/cappuccino-disablesleep"

# Resolve the REAL user. Prefer CAPPUCCINO_USER (the app passes it, because under the native
# auth sheet this script runs as root with SUDO_USER unset), then SUDO_USER, then the caller.
USER_NAME="${CAPPUCCINO_USER:-${SUDO_USER:-$(id -un)}}"
# Never install a root-owned grant (useless): if we resolved to root/empty, fall back to the
# GUI console user, and refuse if still unresolved.
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
  USER_NAME="$(stat -f%Su /dev/console 2>/dev/null || true)"
fi
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
  echo "error: could not resolve a non-root user for the grant; refusing to install." >&2
  exit 1
fi

# Run privileged steps with sudo normally, but directly when ALREADY root (the app installs
# this via one native macOS auth sheet, so there is no Terminal and no inner sudo prompt).
SUDO="sudo"
[ "$(id -u)" -eq 0 ] && SUDO=""

# Source of truth for the grant line: the repo/bundle template if present, else the identical
# inline string.
TEMPLATE="$SCRIPT_DIR/cappuccino.sudoers.template"
if [ -f "$TEMPLATE" ]; then
  GRANT="$(sed "s/__USER__/$USER_NAME/" "$TEMPLATE")"
else
  GRANT="$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset displaysleepnow"
fi

echo "Cappuccino will install this passwordless grant at $SUDOERS_DST (root:wheel, 0440):"
echo ""
echo "    $GRANT"
echo ""
echo "It permits ONLY pmset disablesleep 0/1 and displaysleepnow. Nothing else."
if [ "${1:-}" != "--yes" ] && [ "${1:-}" != "-y" ]; then
  read -r -p "Continue? [y/N] " reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 1 ;; esac
fi

TMP="$(mktemp)"
printf '%s\n' "$GRANT" > "$TMP"
if ! $SUDO visudo -cf "$TMP" >/dev/null; then
  echo "error: generated sudoers failed validation; not installing." >&2
  rm -f "$TMP"; exit 1
fi
$SUDO install -m 0440 -o root -g wheel "$TMP" "$SUDOERS_DST"
rm -f "$TMP"
$SUDO visudo -c >/dev/null && echo "grant installed and sudoers parses cleanly ($SUDOERS_DST)."
