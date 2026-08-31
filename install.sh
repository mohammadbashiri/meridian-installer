#!/bin/sh
set -eu

REPOSITORY="${MERIDIAN_REPOSITORY:-mohammadbashiri/meridian}"
RELEASE_BASE="${MERIDIAN_RELEASE_BASE:-https://github.com/${REPOSITORY}/releases/latest/download}"
BIN_DIRECTORY="${MERIDIAN_BIN_DIR:-$HOME/.local/bin}"
DATA_DIRECTORY="${MERIDIAN_INSTALL_DATA:-$HOME/.local/share/meridian}"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  echo "Meridian release installer currently supports Apple Silicon macOS only." >&2
  exit 1
fi
for command in curl shasum tar mktemp; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 1; }
done

TEMPORARY="$(mktemp -d "${TMPDIR:-/tmp}/meridian-install.XXXXXX")"
cleanup() { rm -rf "$TEMPORARY"; }
trap cleanup EXIT HUP INT TERM

ARCHIVE="$TEMPORARY/meridian-release.tar.gz"
CHECKSUMS="$TEMPORARY/SHA256SUMS"
if [ -n "${MERIDIAN_ARCHIVE:-}" ]; then
  cp "$MERIDIAN_ARCHIVE" "$ARCHIVE"
  [ -n "${MERIDIAN_CHECKSUMS:-}" ] || { echo "MERIDIAN_CHECKSUMS is required with MERIDIAN_ARCHIVE." >&2; exit 1; }
  cp "$MERIDIAN_CHECKSUMS" "$CHECKSUMS"
elif command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
  echo "Downloading the latest Meridian release with GitHub CLI authentication..."
  gh release download --repo "$REPOSITORY" --pattern 'meridian-*.tar.gz' --pattern SHA256SUMS --dir "$TEMPORARY"
  ARCHIVE="$(find "$TEMPORARY" -maxdepth 1 -name 'meridian-*.tar.gz' -type f | head -n 1)"
  CHECKSUMS="$TEMPORARY/SHA256SUMS"
  [ -n "$ARCHIVE" ] && [ -f "$CHECKSUMS" ] || { echo "The latest Meridian release is incomplete." >&2; exit 1; }
else
  echo "Downloading Meridian release metadata..."
  curl -fL --retry 3 --proto '=https' --tlsv1.2 "$RELEASE_BASE/SHA256SUMS" -o "$CHECKSUMS"
  ARCHIVE_NAME="$(awk '$2 ~ /\.tar\.gz$/ { print $2; exit }' "$CHECKSUMS")"
  [ -n "$ARCHIVE_NAME" ] || { echo "No Meridian release archive was listed in SHA256SUMS." >&2; exit 1; }
  echo "Downloading Meridian $ARCHIVE_NAME..."
  curl -fL --retry 3 --proto '=https' --tlsv1.2 "$RELEASE_BASE/$ARCHIVE_NAME" -o "$ARCHIVE"
fi

ARCHIVE_NAME="$(awk '$2 ~ /\.tar\.gz$/ { print $2; exit }' "$CHECKSUMS")"
[ -n "$ARCHIVE_NAME" ] || { echo "No Meridian release archive was listed in SHA256SUMS." >&2; exit 1; }
EXPECTED="$(awk -v name="$ARCHIVE_NAME" '$2 == name { print $1; exit }' "$CHECKSUMS")"
[ -n "$EXPECTED" ] || { echo "Checksum entry not found for $ARCHIVE_NAME." >&2; exit 1; }
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[ "$EXPECTED" = "$ACTUAL" ] || { echo "Meridian archive checksum verification failed." >&2; exit 1; }
echo "Checksum verified."

EXTRACTED="$TEMPORARY/extracted"
mkdir -p "$EXTRACTED"
tar -xzf "$ARCHIVE" -C "$EXTRACTED"
BUNDLE="$(find "$EXTRACTED" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$BUNDLE" ] || { echo "Meridian archive has an invalid layout." >&2; exit 1; }
BINARY_SOURCE="$BUNDLE/bin/meridian"
SKILL_SOURCE="$BUNDLE/skills/meridian/SKILL.md"
[ -x "$BINARY_SOURCE" ] && [ -f "$SKILL_SOURCE" ] || { echo "Meridian archive is incomplete." >&2; exit 1; }

VERSION="$(basename "$BUNDLE" | sed 's/^meridian-//')"
[ -n "$VERSION" ] || { echo "Could not determine Meridian release version." >&2; exit 1; }
mkdir -p "$BIN_DIRECTORY" "$DATA_DIRECTORY/versions"
TARGET="$DATA_DIRECTORY/versions/$VERSION"
rm -rf "$TARGET"
mkdir -p "$TARGET/bin" "$TARGET/skills/meridian"
cp "$BINARY_SOURCE" "$TARGET/bin/meridian"
chmod 755 "$TARGET/bin/meridian"
cp "$SKILL_SOURCE" "$TARGET/skills/meridian/SKILL.md"
ln -s "versions/$VERSION" "$DATA_DIRECTORY/current.new.$$"
# On macOS, mv follows a destination symlink to a directory unless -h is used.
# -h replaces current itself, atomically switching the installed version.
mv -hf "$DATA_DIRECTORY/current.new.$$" "$DATA_DIRECTORY/current"

cat > "$BIN_DIRECTORY/meridian.new.$$" <<EOF
#!/bin/sh
exec "$DATA_DIRECTORY/current/bin/meridian" "\$@"
EOF
chmod 755 "$BIN_DIRECTORY/meridian.new.$$"
mv -f "$BIN_DIRECTORY/meridian.new.$$" "$BIN_DIRECTORY/meridian"

UNINSTALL_SOURCE="$BUNDLE/scripts/meridian-uninstall"
[ -f "$UNINSTALL_SOURCE" ] || { echo "Meridian archive is missing its uninstall command." >&2; exit 1; }
cp "$UNINSTALL_SOURCE" "$BIN_DIRECTORY/meridian-uninstall.new.$$"
chmod 755 "$BIN_DIRECTORY/meridian-uninstall.new.$$"
mv -f "$BIN_DIRECTORY/meridian-uninstall.new.$$" "$BIN_DIRECTORY/meridian-uninstall"

install_skill() {
  agent_home="$1"
  [ -d "$agent_home" ] || return 0
  destination="$agent_home/skills/meridian"
  mkdir -p "$destination"
  cp "$SKILL_SOURCE" "$destination/SKILL.md"
  echo "Installed agent skill: $destination/SKILL.md"
}
install_skill "${PI_AGENT_HOME:-$HOME/.pi/agent}"
install_skill "${CLAUDE_HOME:-$HOME/.claude}"
install_skill "${CODEX_HOME:-$HOME/.codex}"

if [ "$BIN_DIRECTORY" = "$HOME/.local/bin" ] && [ "${MERIDIAN_NO_PATH_UPDATE:-0}" != "1" ]; then
  PROFILE="${MERIDIAN_SHELL_PROFILE:-$HOME/.zprofile}"
  PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
  touch "$PROFILE"
  if ! grep -F "$PATH_LINE" "$PROFILE" >/dev/null 2>&1; then
    printf '\n# Meridian command\n%s\n' "$PATH_LINE" >> "$PROFILE"
    echo "Added ~/.local/bin to PATH in $PROFILE (applies to new shells)."
  fi
fi

echo "Installed Meridian $VERSION"
echo "CLI: $BIN_DIRECTORY/meridian"
echo "Run meridian-uninstall to remove Meridian while preserving vaults and local state."
