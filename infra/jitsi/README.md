# Jitsi staging deployment

**Retired on 12 October 2026:** the user selected doctor-entered Google Meet links. This bundle remains for historical reference and is not part of the current deployment. No Jitsi host or credentials are required by the active app.

The pinned official release and archive checksum are in `release.json`. The generated private server configuration is under ignored `.codex-runtime/jitsi`. It enables JWT authentication, rejects empty tokens and generates fresh internal service passwords. No patient data, SMTP credential or provider key is committed here.

Deployment was not executed: Docker/WSL is absent on this Windows machine, and the connected AWS account denied EC2 inspection in Singapore and Virginia through an organization service-control policy. No cloud instance, network or billable staging service was created. An accessible, approved Linux host is required.

Provide a staging hostname pointing to that host, Docker Engine/Compose, valid HTTPS, TCP 80/443 and UDP 10000. Set `JITSI_BASE_URL` to its HTTPS origin, then run `node tool/prepare_jitsi_configuration.mjs` from the workspace. Keep the generated `.env` private; transfer it securely to the designated host. Run `infra/jitsi/install.sh` there with the config path, archive URL and checksum from `release.json`. The script validates the archive and refuses the placeholder hostname.

Configure `JVB_ADVERTISE_IPS` on a host behind NAT as described in the [official Docker guide](https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker/). The generated configuration assumes a directly reachable host. Confirm certificate issuance and that received UDP media crosses the host firewall before accepting the deployment.

Install the generated `JITSI_BASE_URL`, `JITSI_APP_ID` and `JITSI_APP_SECRET` in Supabase server secrets. Set `JITSI_STAGING_CONSULTATION_IDS` to the comma-separated synthetic consultation IDs eligible for staging. Other rooms keep their existing provider. The Edge endpoint first runs the existing participant/time/room authorization RPC, then signs a token for that exact room and current identity. Tokens expire within five minutes and never beyond the appointment window. The client validates the returned HTTPS provider origin.

The signed-in assigned doctor and patient should join through CareNavigator. Run the Playwright media test on the same staged consultation; verify received tracks on both browsers, audio as well as video, terminal room closure and rejection of unrelated users. JWT cryptographic tests and live application authorization tests alone do not prove successful provider deployment or exchanged media.

For shutdown, use `docker compose down` on the designated staging directory and remove only the associated temporary cloud resources through their owning cloud provider. Clear the staging consultation allowlist when those fixtures are retired. Keep configuration backups and credentials private.
