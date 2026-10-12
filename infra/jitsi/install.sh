#!/usr/bin/env bash
set -euo pipefail
umask 077
# Invoke only on the designated Linux staging host, with the generated private .env.
config_file=${1:?Pass the private staging .env path}
archive_url=${2:?Pass the pinned archive URL from release.json}
archive_sha=${3:?Pass the pinned SHA256 from release.json}
if ! command -v docker >/dev/null || ! docker compose version >/dev/null; then
  echo 'Docker Engine and the Docker Compose plugin are required.' >&2; exit 1
fi
if grep -q 'example.test' "$config_file"; then
  echo 'Set a real Jitsi hostname before deployment.' >&2; exit 1
fi
install_root=/opt/carenavigator-jitsi
mkdir -p "$install_root"
archive_file=$(mktemp)
trap 'rm -f "$archive_file"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 "$archive_url" --output "$archive_file"
printf '%s  %s\n' "$archive_sha" "$archive_file" | sha256sum --check --status
unzip -q "$archive_file" -d "$install_root"
release_directory=$(find "$install_root" -mindepth 1 -maxdepth 1 -type d -name 'docker-jitsi-meet-*' | sort | tail -n 1)
test -n "$release_directory"
install -m 600 "$config_file" "$release_directory/.env"
mkdir -p "$install_root/config"/{web/crontabs,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb}
cd "$release_directory"
docker compose pull
docker compose up -d
docker compose ps
