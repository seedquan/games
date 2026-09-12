#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_binary="${GODOT_BIN:-}"
if [[ -z "$godot_binary" ]]; then
  for command_name in godot godot4; do
    if command -v "$command_name" >/dev/null 2>&1; then
      godot_binary="$(command -v "$command_name")"
      break
    fi
  done
fi
if [[ -z "$godot_binary" ]]; then
  for candidate in \
    /Applications/Godot.app/Contents/MacOS/Godot \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Applications/Godot (Managed by Ziva).app/Contents/MacOS/Godot"; do
    if [[ -x "$candidate" ]]; then
      godot_binary="$candidate"
      break
    fi
  done
fi
if [[ -z "$godot_binary" || ! -x "$godot_binary" ]]; then
  echo "Godot 4.7+ was not found. Set GODOT_BIN to the Godot executable's absolute path." >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  set -- --editor
elif [[ "$1" == "--play" ]]; then
  shift
fi
exec "$godot_binary" --path "$project_dir" "$@"
