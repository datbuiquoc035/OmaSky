#!/usr/bin/env bash
# omarchy:summary=Install the OmaSky plugin locally from this checkout
# omarchy:group=plugin
# omarchy:args=[options]

# Local installer for the qdot.omasky Omarchy plugin.
#
# Copies this checkout into ~/.config/omarchy/plugins/qdot.omasky/, validates
# and enables it as a bar widget, and — by default — swaps the old
# qdot.omashard + qdot.omaevents entries in shell.json for the single
# qdot.omasky entry (backing the file up first).
#
# Usage:
#   scripts/install.sh                 # install, enable, and swap the old widgets
#   scripts/install.sh --section left  # place the widget in the left section
#   scripts/install.sh --keep-old      # install but leave the old widgets in shell.json
#   scripts/install.sh --no-enable     # copy the plugin but leave it disabled
#   scripts/install.sh --force         # replace an existing install
#   scripts/install.sh --remove        # uninstall (alias: --rollback)

set -euo pipefail

PLUGIN_ID="qdot.omasky"
PLUGINS_DIR="${HOME}/.config/omarchy/plugins"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"
SHELL_JSON="${HOME}/.config/omarchy/shell.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

ACTION="install"
FORCE=0
NO_ENABLE=0
KEEP_OLD=0
SECTION="right"

fail() {
  echo "install.sh: $*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: scripts/install.sh [options]

Local installer for the $PLUGIN_ID Omarchy plugin.

Options:
  --section <left|center|right>  Bar section to place the widget in (default: right)
  --keep-old                     Install but leave qdot.omashard/qdot.omaevents in shell.json
  --no-enable                    Copy the plugin but do not enable it
  --force                        Replace an existing install instead of failing
  --remove, --rollback           Uninstall the plugin from this machine
  -h, --help                     Show this help
USAGE
}

parse_options() {
  while (( $# > 0 )); do
    case "$1" in
      --section)
        SECTION="${2:-}"
        [[ -n $SECTION ]] || fail "--section requires left, center or right"
        [[ $SECTION =~ ^(left|center|right)$ ]] || fail "section must be left, center, or right"
        shift 2
        ;;
      --keep-old)
        KEEP_OLD=1
        shift
        ;;
      --no-enable)
        NO_ENABLE=1
        shift
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --remove | --rollback)
        ACTION="remove"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1 (try --help)"
        ;;
    esac
  done
}

require_omarchy() {
  command -v omarchy-shell >/dev/null 2>&1 ||
    fail "omarchy-shell not found — this script installs an Omarchy plugin"
}

remove_plugin() {
  [[ -e $TARGET || -L $TARGET ]] || { echo "OmaSky is not installed."; exit 0; }
  rm -rf "$TARGET"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo "Removed OmaSky from $TARGET"
}

stage_and_validate() {
  local stage="$1"
  mkdir -p "$PLUGINS_DIR"
  cp -a "$REPO_DIR/." "$stage/"
  rm -rf "$stage/.git" "$stage/__pycache__"
  find "$stage" -name '*.pyc' -delete

  if command -v omarchy-plugin-validate >/dev/null 2>&1; then
    omarchy-plugin-validate "$stage" || fail "plugin folder failed validation"
  elif ! jq -e . "$stage/manifest.json" >/dev/null 2>&1; then
    fail "manifest.json is not valid JSON and omarchy-plugin-validate is unavailable"
  fi
}

enable_plugin() {
  local discovered=0
  for (( attempt = 0; attempt < 40; attempt++ )); do
    if omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" '
        any(.[]; .id == $id)' >/dev/null; then
      discovered=1
      break
    fi
    sleep 0.05
  done
  (( discovered )) || fail "installed plugin '$PLUGIN_ID' was not discovered; enable it with: omarchy plugin enable $PLUGIN_ID"
  omarchy-plugin-enable "$PLUGIN_ID" --section "$SECTION"
}

# Replace the old qdot.omashard / qdot.omaevents shell.json entries with a
# single qdot.omasky entry, keeping any inline settings from whichever old
# widget was found first. Backs up shell.json first.
swap_shell_entries() {
  [[ -f $SHELL_JSON ]] || { echo "No shell.json at $SHELL_JSON — skipping widget swap."; return 0; }

  local backup="$SHELL_JSON.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SHELL_JSON" "$backup"
  echo "Backed up shell.json -> $backup"

  if ! python3 - "$SHELL_JSON" <<'PY'
import json
import sys

path = sys.argv[1]
old_ids = {"qdot.omashard", "qdot.omaevents"}
new_id = "qdot.omasky"
# Keys inherited from the old widgets that do not map onto the unified
# plugin's settings (each old plugin had its own "format" vocabulary).
skip_keys = {"format"}

with open(path) as handle:
    config = json.load(handle)

# shell.json nests the layout under "bar"; tolerate a bare top-level layout too.
layout = config.get("bar", {}).get("layout")
if not isinstance(layout, dict):
    layout = config.get("layout")
if not isinstance(layout, dict):
    print("shell.json: no layout object to swap; leaving as-is")
    raise SystemExit(0)

first_section = None
first_index = None
merged = {}
for section in ("left", "center", "right"):
    entries = layout.get(section)
    if not isinstance(entries, list):
        continue
    for index, entry in enumerate(entries):
        if isinstance(entry, dict) and entry.get("id") in old_ids:
            if first_index is None:
                first_index = index
                first_section = section
                merged = {key: value for key, value in entry.items() if key != "id" and key not in skip_keys}
            else:
                for key, value in entry.items():
                    if key != "id" and key not in skip_keys and key not in merged:
                        merged[key] = value

if first_index is None:
    print("shell.json: no qdot.omashard/qdot.omaevents entries found; leaving as-is")
    raise SystemExit(0)

layout[first_section][first_index] = {"id": new_id, **merged}
for section in ("left", "center", "right"):
    entries = layout.get(section)
    if isinstance(entries, list):
        layout[section] = [
            entry for entry in entries
            if not (isinstance(entry, dict) and entry.get("id") in old_ids)
        ]

with open(path, "w") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
print(f"shell.json: replaced qdot.omashard/qdot.omaevents with {new_id}")
PY
  then
    fail "swapping shell.json entries failed"
  fi
}

install_plugin() {
  [[ -e $TARGET || -L $TARGET ]] && {
    if (( FORCE )); then
      echo "Replacing existing install at $TARGET"
      rm -rf "$TARGET"
    else
      fail "OmaSky is already installed at $TARGET (use --force to reinstall)"
    fi
  }

  local stage
  stage="$(mktemp -d "$PLUGINS_DIR/.install.$PLUGIN_ID.XXXXXX")"
  local committed=0
  cleanup() {
    [[ -d ${stage:-} ]] && rm -rf "$stage"
    (( committed )) || rm -rf "$TARGET"
  }
  trap cleanup EXIT

  stage_and_validate "$stage"
  mv "$stage" "$TARGET"
  stage=""
  committed=1
  echo "Installed $PLUGIN_ID into $TARGET"

  if (( KEEP_OLD )); then
    echo "Keeping the existing qdot.omashard/qdot.omaevents shell.json entries."
  else
    swap_shell_entries
  fi

  omarchy-shell shell rescanPlugins >/dev/null || true

  if (( NO_ENABLE )); then
    echo "Enable it later with: omarchy plugin enable $PLUGIN_ID --section $SECTION"
  else
    enable_plugin
  fi
}

parse_options "$@"
require_omarchy

if [[ $ACTION == "remove" ]]; then
  remove_plugin
else
  install_plugin
fi