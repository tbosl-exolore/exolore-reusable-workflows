# Public repository security review

This repository is intentionally public. Keep caller secrets and infrastructure-specific values out of central files, examples, tests, issues copied into docs, and release notes.

## Required controls

- Do not add tokens, SSH private keys, `.env` values, production hostnames/IPs, customer identifiers, or logs from consumer runs.
- Keep example hosts and domain names reserved for documentation, such as `example.invalid`.
- Publish only image digests in release contracts. Never print GHCR credentials or SSH private keys.
- Keep SSH host-key checking enabled and the private key on the consuming Environment only.
- Keep `GITHUB_TOKEN` permissions minimal and scoped to the caller repository. Do not use `secrets: inherit`.
- Check out the caller source at the caller SHA and the shared scripts at the called workflow SHA.
- Review changes to any shell file that is sourced or executed from a caller repository as privileged code; deployment approval should gate the whole production job.

The automated public-content check blocks common credential formats, private key blocks, internal repository names used during design, and private IPv4 address literals. It is a guardrail, not a substitute for reviewing the full public diff.
