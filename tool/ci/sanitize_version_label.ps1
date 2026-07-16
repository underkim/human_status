# Derives a filesystem-safe version label for release archive names from
# INPUT_VERSION_LABEL (workflow_dispatch input) / REF_NAME (git ref), both
# read only from the environment -- never interpolated into this script's
# text -- so their content cannot inject shell syntax. Prints the sanitized
# label to stdout. Shared by the Windows job in
# .github/workflows/release-artifacts.yml and by
# test/release_artifacts_version_label_test.dart, so the two can't drift.
$ErrorActionPreference = 'Stop'

$raw = $env:INPUT_VERSION_LABEL
if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $env:REF_NAME }
if ([string]::IsNullOrWhiteSpace($raw)) { $raw = 'dev' }

# Anything outside a conservative filename charset becomes a dash.
$sanitized = [regex]::Replace($raw, '[^A-Za-z0-9._-]', '-')
# Leading/trailing dots are unsafe in a filename segment (e.g. could read as
# "..", or as a hidden file), so strip them before and after truncation.
$sanitized = $sanitized.Trim('.')
if ($sanitized.Length -gt 64) { $sanitized = $sanitized.Substring(0, 64) }
$sanitized = $sanitized.Trim('.')

if ([string]::IsNullOrWhiteSpace($sanitized)) { $sanitized = 'dev' }

Write-Output $sanitized
