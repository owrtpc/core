#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Native Linux x64 CI. Scanner archives are pinned to official SHA-256 digests.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/owrtpc-security.XXXXXX)
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz -o "$work/gitleaks.tar.gz"
echo "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  $work/gitleaks.tar.gz" | sha256sum -c -
tar -xzf "$work/gitleaks.tar.gz" -C "$work"
"$work/gitleaks" git . --redact --log-opts=--all
curl -fsSL --retry 3 https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz -o "$work/shellcheck.tar.xz"
echo "8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198  $work/shellcheck.tar.xz" | sha256sum -c -
tar -xJf "$work/shellcheck.tar.xz" -C "$work"
# BusyBox ash is the target dialect. OpenWrt config_get/json_get_var assign
# variables by name; rc.common and sourced libraries consume their globals.
# SC2154/SC2034 cannot model those APIs; all other warning/error rules remain on.
git ls-files owrtpc/files | while IFS= read -r file; do
    if grep -q '^#!/bin/sh' "$file"; then
        "$work/shellcheck-v0.11.0/shellcheck" --shell=busybox \
            --severity=warning --exclude=SC2034,SC2154 "$file"
    fi
done
