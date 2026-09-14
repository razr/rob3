#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$repo_root/.kiro/skills"
target_dir="$repo_root/.github/skills"

if [[ ! -d "$source_dir" ]]; then
    printf 'missing skill source: %s\n' "$source_dir" >&2
    exit 1
fi

rm -rf "$target_dir"
mkdir -p "$target_dir"
for skill_dir in "$source_dir"/*; do
    if [[ -d "$skill_dir" && ! -L "$skill_dir" ]]; then
        cp -a "$skill_dir" "$target_dir/"
    fi
done
printf 'synced Kiro skills to Copilot: %s -> %s\n' "$source_dir" "$target_dir"
