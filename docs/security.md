# Public repository security review

This repository is intentionally public. Keep caller secrets and infrastructure-specific values out of central files, examples, tests, issues copied into docs, and release notes.

## Required controls

- Do not add tokens, SSH private keys, `.env` values, production hostnames/IPs, customer identifiers, or logs from consumer runs.
- Keep example hosts and domain names reserved for documentation, such as `example.invalid`.
- Publish only image digests in release contracts. Never print GHCR credentials or SSH private keys.
- Keep SSH host-key checking enabled and the private key on the consuming Environment only.
- Keep `GITHUB_TOKEN` permissions minimal and scoped to the caller repository. Explicitly forward only `DEPLOY_SSH_KEY` and `SSH_KNOWN_HOSTS` by name to the deployment workflow; do not use `secrets: inherit`.
- Check out the caller source at the caller SHA and the shared scripts at the called workflow SHA.
- Review changes to any shell file that is sourced or executed from a caller repository as privileged code; deployment approval should gate the whole production job.

The automated public-content check blocks common credential formats, private key blocks, internal repository names used during design, and private IPv4 address literals. It is a guardrail, not a substitute for reviewing the full public diff.

## Additional release files

The deployment workflow accepts only newline-separated repository-relative paths. It validates each path against the exact caller `SOURCE_SHA` and reads regular-file blobs from that Git commit, not the runner's mutable working tree. Absolute paths, `.`/`..` components, Windows separators, missing paths, duplicate/overlapping selections, and collisions with managed archive entries are rejected. Symlinks, Git submodules, and other non-regular Git entries are rejected. Git executable mode is preserved as `0755`; non-executable files are packaged as `0644`, without ownership or special mode bits.

Selections containing `.git*`, `.ssh`, `.aws`, `.docker`, credential/secret/token/private-key names, `.env*`, `*.env`, or common private-key extensions are rejected. Do not select files containing secrets or runtime values even if their names do not match these patterns. This filename guard is not a general secret-content scanner; consumers remain responsible for reviewing the explicit files and directories they request.
