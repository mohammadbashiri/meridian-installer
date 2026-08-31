#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/meridian-installer-test.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT HUP INT TERM

make_archive() {
  version="$1"
  bundle="$WORK/bundle/meridian-$version"
  archive="$WORK/meridian-$version.tar.gz"
  checksums="$WORK/SHA256SUMS-$version"

  mkdir -p "$bundle/bin" "$bundle/skills/meridian" "$bundle/scripts"
  printf '#!/bin/sh\necho %s\n' "$version" > "$bundle/bin/meridian"
  chmod 755 "$bundle/bin/meridian"
  printf '%s\n' '---' > "$bundle/skills/meridian/SKILL.md"
  printf '#!/bin/sh\n' > "$bundle/scripts/meridian-uninstall"
  tar -czf "$archive" -C "$WORK/bundle" "meridian-$version"
  (cd "$WORK" && shasum -a 256 "$(basename "$archive")") > "$checksums"

  printf '%s\n%s\n' "$archive" "$checksums"
}

install_version() {
  version="$1"
  set -- $(make_archive "$version")
  MERIDIAN_ARCHIVE="$1" \
  MERIDIAN_CHECKSUMS="$2" \
  MERIDIAN_BIN_DIR="$WORK/bin" \
  MERIDIAN_INSTALL_DATA="$WORK/data" \
  MERIDIAN_NO_PATH_UPDATE=1 \
  PI_AGENT_HOME="$WORK/no-pi" \
  CLAUDE_HOME="$WORK/no-claude" \
  CODEX_HOME="$WORK/no-codex" \
  "$ROOT/install.sh" >/dev/null
}

install_version 0.3.8
install_version 0.3.9

[ "$(readlink "$WORK/data/current")" = "versions/0.3.9" ]
[ -z "$(find "$WORK/data/versions/0.3.8" -mindepth 1 -maxdepth 1 -name 'current.new.*' -print -quit)" ]
[ "$("$WORK/bin/meridian")" = "0.3.9" ]

echo 'installer upgrade test passed'
