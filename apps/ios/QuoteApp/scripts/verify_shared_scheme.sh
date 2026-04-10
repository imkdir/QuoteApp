#!/usr/bin/env bash
set -euo pipefail

scheme_path="QuoteApp.xcodeproj/xcshareddata/xcschemes/QuoteApp.xcscheme"

if [[ ! -f "${scheme_path}" ]]; then
  echo "error: missing shared Xcode scheme at ${scheme_path}" >&2
  exit 1
fi

if ! grep -q 'BlueprintName = "QuoteApp"' "${scheme_path}"; then
  echo "error: scheme at ${scheme_path} does not reference target QuoteApp" >&2
  exit 1
fi

if ! grep -q "<BuildableProductRunnable" "${scheme_path}"; then
  echo "error: scheme at ${scheme_path} is missing a runnable app action" >&2
  exit 1
fi

echo "verified shared scheme: ${scheme_path}"
