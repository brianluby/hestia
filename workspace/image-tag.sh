#!/usr/bin/env bash
# Prints the image the `hestia` launcher builds and runs: hestia-pi:<hash of the
# build inputs of the Dockerfile's `pi` target>. A changed input (for example
# after `git pull`) gives a new tag, which the launcher builds once; an
# unchanged one never rebuilds. Old tags are left alone.
#
# usage: image-tag.sh [<context-dir>]     (default: the repository root)
#
# Inputs: the Dockerfile and every path COPYed by the base, fixture-tools, nono
# and pi stages. tests/hestia-image-tag.test.sh fails when a COPY is missing here.
# shortcut: .dockerignore is not applied beyond .DS_Store, so an ignored file
# inside these paths changes the tag (one extra build), never hides a change.
set -euo pipefail

ctx="${1:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ctx"
sum="$(find Dockerfile fixtures/synthetic agent/nono -type f ! -name .DS_Store -exec shasum -a 256 {} + |
	LC_ALL=C sort | shasum -a 256 | cut -c1-12)"
printf 'hestia-pi:%s\n' "$sum"
