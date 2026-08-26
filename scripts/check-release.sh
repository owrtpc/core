#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

PROJECT_DIR=${1:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}

fail() {
	printf 'Release blocked: %s\n' "$*" >&2
	exit 1
}

git -C "$PROJECT_DIR" rev-parse --show-toplevel >/dev/null 2>&1 ||
	fail 'not a Git working tree.'

branch=$(git -C "$PROJECT_DIR" symbolic-ref --quiet HEAD) ||
	fail 'detached HEAD; check out main first.'
[ "$branch" = refs/heads/main ] ||
	fail 'release builds must use main.'

dirty=$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=all --ignore-submodules=none)
[ -z "$dirty" ] || fail 'uncommitted changes; commit all changes before building.'
commit=$(git -C "$PROJECT_DIR" rev-parse HEAD)
git -C "$PROJECT_DIR" log -1 --format=%B | grep -Eq '^Signed-off-by: .+ <[^>]+>$' ||
	fail 'HEAD lacks a DCO Signed-off-by trailer.'

# Query the server, not a possibly stale origin/main tracking ref.
remote_refs=$(git -C "$PROJECT_DIR" ls-remote --exit-code origin refs/heads/main) ||
	fail 'cannot verify origin/main; check network access and push first.'
remote_commit=$(printf '%s\n' "$remote_refs" | awk '$2 == "refs/heads/main" { print $1 }')
[ "$commit" = "$remote_commit" ] ||
	fail 'HEAD differs from origin/main; synchronize and push before building.'

python3 "$PROJECT_DIR/scripts/check-ci.py" "$commit" >&2 ||
	fail 'CI must pass for the exact pushed commit before building.'

# Refuse local changes made while the remote query was in flight.
[ "$(git -C "$PROJECT_DIR" rev-parse HEAD)" = "$commit" ] ||
	fail 'HEAD changed during verification; retry.'
dirty=$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=all --ignore-submodules=none)
[ -z "$dirty" ] || fail 'uncommitted changes appeared during verification.'
printf '%s\n' "$commit"
