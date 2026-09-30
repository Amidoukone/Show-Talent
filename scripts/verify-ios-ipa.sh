#!/usr/bin/env bash
set -euo pipefail

# Run on the Codemagic macOS builder after flutter build ipa and before upload.
expected_bundle_id="${1:?Expected iOS bundle ID is required}"
expected_aps_environment="${2:-production}"
ipa_path="${3:-}"

if [[ -z "$ipa_path" ]]; then
  shopt -s nullglob
  ipa_files=(build/ios/ipa/*.ipa)
  if [[ ${#ipa_files[@]} -ne 1 ]]; then
    echo "Expected exactly one IPA in build/ios/ipa; found ${#ipa_files[@]}." >&2
    exit 1
  fi
  ipa_path="${ipa_files[0]}"
fi

verify_dir="$(mktemp -d)"
trap 'rm -rf "$verify_dir"' EXIT
unzip -q "$ipa_path" -d "$verify_dir"
app_path="$(find "$verify_dir/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "No app bundle found in IPA." >&2
  exit 1
fi

codesign --verify --strict "$app_path"
codesign -d --entitlements :- "$app_path" > "$verify_dir/entitlements.plist" 2> "$verify_dir/codesign.log"
actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
actual_aps_environment="$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$verify_dir/entitlements.plist" 2>/dev/null || true)"
associated_domain="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.associated-domains:0' "$verify_dir/entitlements.plist" 2>/dev/null || true)"

if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
  echo "IPA bundle ID mismatch: $actual_bundle_id (expected $expected_bundle_id)." >&2
  exit 1
fi
if [[ "$actual_aps_environment" != "$expected_aps_environment" ]]; then
  echo "Signed APNs entitlement mismatch: ${actual_aps_environment:-missing} (expected $expected_aps_environment)." >&2
  exit 1
fi
if [[ "$associated_domain" != "applinks:adfoot.org" ]]; then
  echo "Signed associated domain mismatch: ${associated_domain:-missing}." >&2
  exit 1
fi

echo "Verified signed IPA: bundle=$actual_bundle_id, APNs=$actual_aps_environment, domain=$associated_domain"
