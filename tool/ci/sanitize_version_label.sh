#!/usr/bin/env bash
# Derives a filesystem-safe version label for release archive names from
# INPUT_VERSION_LABEL (workflow_dispatch input) / REF_NAME (git ref), both
# read only from the environment -- never interpolated into this script's
# text -- so their content cannot inject shell syntax. Prints the sanitized
# label to stdout. Shared by the Ubuntu job in
# .github/workflows/release-artifacts.yml and by
# test/release_artifacts_version_label_test.dart, so the two can't drift.
set -euo pipefail

raw="${INPUT_VERSION_LABEL:-}"
if [ -z "$raw" ]; then
  raw="${REF_NAME:-}"
fi
if [ -z "$raw" ]; then
  raw="dev"
fi

# Anything outside a conservative filename charset becomes a dash.
sanitized=$(printf '%s' "$raw" | sed 's/[^A-Za-z0-9._-]/-/g')
# Leading/trailing dots are unsafe in a filename segment (e.g. could read as
# "..", or as a hidden file), so strip them before and after truncation.
sanitized=$(printf '%s' "$sanitized" | sed 's/^\.*//; s/\.*$//')
sanitized="${sanitized:0:64}"
sanitized=$(printf '%s' "$sanitized" | sed 's/^\.*//; s/\.*$//')

if [ -z "$sanitized" ]; then
  sanitized="dev"
fi

printf '%s' "$sanitized"
