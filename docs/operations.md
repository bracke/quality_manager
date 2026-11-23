# Operations Guide

## Deployment

Build and validate a source revision with `alr build --validation -- -f` and `alr test`. Install the binary, an
absolute-path production configuration, and one deployment mode from `deploy/systemd/`. Never run the continuous
service and maintenance timer against the same coordinator database. Before enabling either, run:

```text
quality-manager --config /etc/quality-manager/quality-manager.toml doctor
quality-manager --config /etc/quality-manager/quality-manager.toml --format json status
```

Monitor the unit journal and the `status`, `queue`, `approvals`, `events`, and `recover` views. An unhealthy or
blocked project does not justify deleting durable state or weakening an approval policy.

## Database Backup

The coordinator database is a primary file plus an optional `.fts` companion. A filesystem copy is valid only
while every writer is stopped. Stop the selected unit and confirm no Quality Manager process remains. Then create a
private snapshot directory and copy both files while preserving modes:

```text
systemctl stop quality-manager.service
install -d -m 0700 /var/backups/quality-manager/2026-11-23T120000Z
cp --preserve=mode /var/lib/quality-manager/quality-manager.db /var/backups/quality-manager/2026-11-23T120000Z/
cp --preserve=mode /var/lib/quality-manager/quality-manager.db.fts /var/backups/quality-manager/2026-11-23T120000Z/
sha256sum /var/backups/quality-manager/2026-11-23T120000Z/* > /var/backups/quality-manager/2026-11-23T120000Z/SHA256SUMS
```

If `.fts` does not exist, omit it. Copy configuration separately after removing credentials. Restart the unit and
retain backups according to the site's recovery-point policy. Encrypt backup media and restrict it to operators.

## Restore

Stop all writers. Verify `sha256sum -c SHA256SUMS`, restore into a new private directory, and point a temporary
configuration at the restored database. Run read-only `status` first. Only after identity, history, leases, journal,
and queued-work counts are plausible should the restored files replace production. Preserve the failed database for
forensics. Start one scheduler instance and confirm journal reconciliation does not duplicate upstream work.

## Signed Release Artifacts

Create an offline Ed25519 keypair once, export qualified evidence, generate the exact pinned-dependency SBOM, and
sign both artifacts. The private key is created owner-only and must not be committed or stored in the coordinator
database.

```text
quality-manager release-keygen release-signing.key release-signing.pub
quality-manager --config /etc/quality-manager/quality-manager.toml release-export RELEASE evidence.json
quality-manager release-sbom alire.toml sbom.cdx.json
quality-manager release-sign evidence.json release-signing.key
quality-manager release-sign sbom.cdx.json release-signing.key
quality-manager release-verify evidence.json release-signing.pub
quality-manager release-verify sbom.cdx.json release-signing.pub
```

Archive the evidence, SBOM, `.sig` sidecars, public key, source revision, and qualification decision together. Key
rotation creates a new keypair; retain retired public keys for historical verification.
