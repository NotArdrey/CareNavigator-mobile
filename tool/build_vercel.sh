#!/usr/bin/env bash
set -euo pipefail

# Match the SDK used for the verified mobile and web builds.
flutter_version=3.44.8
flutter_sdk="${HOME}/.cache/care-navigator/flutter-${flutter_version}"
if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -x "${flutter_sdk}/bin/flutter" ]; then
    mkdir -p "$(dirname "${flutter_sdk}")"
    git clone --depth 1 --branch "${flutter_version}" \
      https://github.com/flutter/flutter.git "${flutter_sdk}"
  fi
  export PATH="${flutter_sdk}/bin:${PATH}"
fi

flutter config --no-analytics
flutter pub get --enforce-lockfile

# Only public browser configuration belongs in this build. Never load root env.
build_args=(build web --release --no-web-resources-cdn)
for name in NEXT_PUBLIC_SUPABASE_URL NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY APP_BASE_URL; do
  if [ -n "${!name:-}" ]; then
    build_args+=("--dart-define=${name}=${!name}")
  fi
done
flutter "${build_args[@]}"
