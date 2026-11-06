#!/usr/bin/env bash
# ADR-006 step 1 — put `hestia` on PATH from this clone. Needs no sudo, edits no
# shell profile and installs nothing else; safe to re-run.
#
#   git clone https://github.com/brianluby/hestia.git ~/.hestia && ~/.hestia/install.sh
#
# Update: git -C ~/.hestia pull
set -euo pipefail

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Docker is only needed to run hestia, so a problem here is a warning.
if ! command -v docker >/dev/null 2>&1; then
	echo "install: Docker is not installed — install it before running hestia" >&2
elif ! docker info >/dev/null 2>&1; then
	echo "install: the Docker daemon is not reachable — start Docker before running hestia" >&2
fi

# The first of these that is already on PATH and writable without sudo.
dir=""
for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin; do
	case ":$PATH:" in *":$d:"*) ;; *) continue ;; esac
	if [ -d "$d" ] && [ -w "$d" ]; then
		dir="$d"
		break
	fi
done

if [ -z "$dir" ]; then
	echo "install: no writable directory on your PATH. Add this line to your shell profile (e.g. ~/.zshrc), then open a new terminal:" >&2
	echo "export PATH=\"$here:\$PATH\""
	exit 0
fi

link="$dir/hestia"
# Replace only a link that provably points at a Hestia launcher: one sitting in
# a clone that has Hestia's helpers beside it. A name ending in /hestia proves
# nothing, and a dangling link cannot be checked, so both are refused.
if [ -e "$link" ] || [ -L "$link" ]; then
	target="$(readlink "$link" || true)"
	case "$target" in /*) ;; *) target="$dir/$target" ;; esac
	owner="$(dirname "$target")"
	if ! { [ -L "$link" ] && [ "$(basename "$target")" = hestia ] && [ -f "$target" ] &&
		[ -f "$owner/install.sh" ] && [ -f "$owner/identity/workspace-id.sh" ] &&
		[ -f "$owner/workspace/workspace-lifecycle.sh" ]; }; then
		echo "install: $link already exists and is not a link to a Hestia clone; not touching it. Remove it and re-run." >&2
		exit 1
	fi
fi
ln -sfn "$here/hestia" "$link"
echo "installed $link -> $here/hestia"
echo "next: cd <your repository> && hestia      update: git -C $here pull"
