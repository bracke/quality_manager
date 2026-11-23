# Disaster-Recovery Drill

Run this drill at least quarterly and after storage-format or deployment changes. Use an isolated host and copies of
production data; never rehearse by overwriting the active database.

1. Record the backup timestamp, source revision, schema version, expected projects, open work, journal operations,
   and recovery objectives.
2. Select a backup without inspecting its contents first. Verify its checksum manifest and restore the database and
   optional `.fts` companion under an owner-only directory.
3. Configure the same application and pinned integration revisions with all write-producing integrations disabled.
4. Run `doctor`, then JSON `status`, `queue`, `approvals`, `history`, `events`, and `recover`. Compare counts and exact
   identities with the recorded control values.
5. Enable only simulated or disposable upstream projects. Start one `daemon --once --dry-run` cycle and confirm
   leases, prepared/invoking journal entries, and terminal records reconstruct without duplicate dispatches.
6. Repeat the restart during a prepared operation and during reconciliation. Confirm the persisted operation ID is
   adopted rather than invoked twice.
7. Verify a previously signed evidence bundle and SBOM with the archived public key. A one-byte artifact change must
   fail verification.
8. Record recovery-point loss, recovery time, deviations, commands, diagnostics, and corrective actions. The drill
   fails if evidence is silently repaired, a terminal result changes, or an upstream side effect is duplicated.

Do not return a restored coordinator to production until an operator approves the results and all external project,
quality-database, Improve, and model_runner identities match their durable records.
