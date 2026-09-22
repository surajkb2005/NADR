#!/usr/bin/env sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
backend_status=$(git -C "$repository_root" status --porcelain -- backend/)

if [ -n "$backend_status" ]; then
  echo "ERROR: backend/ contains changes:" >&2
  echo "$backend_status" >&2
  git -C "$repository_root" diff -- backend/ >&2
  git -C "$repository_root" diff --cached -- backend/ >&2
  exit 1
fi

echo "Backend unchanged."
