# Required Upstream Changes

## AQ-ID-01 — Durable Ada Quality database identity

Add an installation UUID or durable identity to Ada Quality metadata and expose it through Ada_Quality.Reporting and
coordinator-facing JSON envelopes. It must survive relocation and backup restore, while database replacement at the
same path remains detectable. Add migration, import, and replacement tests.

Implementation design validated against the current schema: migrate to schema version 6, store a canonical
`database_id=<UUID>` in the single schema metadata record, generate it with `Database.UUIDs`, and expose it separately
from `Snapshot_Identity`. Migration must create the UUID and advance the schema in one transaction. Read-only
reporting must validate canonical UUID syntax and never generate or repair an identity.

Status: **implemented and validated** in Ada Quality commit `3a85a5b`. The public reporting API and
`database-statistics` JSON v2 expose the UUID. Atomic migration, reopen stability, independent-store distinction,
schema rejection, full tests, 90.03% coverage, release checking, and GNATdoc generation passed.

## AQS-PAGE-01 — Complete Summary enumeration

Add snapshot-bound cursor pagination to collection JSON or a typed API returning the complete bounded report. Cursors
must bind command and filters and reject snapshot changes instead of shifting rows.

## IMP-APPROVE-01 — Atomic exact approval

Extend Improve with:

    improve plan approve PLAN-ID --revision N --content-sha256 DIGEST

Compare the exact revision and complete persisted-content digest inside the approval transaction. Reject stale latest
revision or digest mismatch without mutation. Include content_sha256 in JSON and audit evidence. Retain the
interactive latest-revision form.

## MR-HEADLESS-01 — Noninteractive native work

Add versioned JSON commands:

    model_runner work capabilities --format json
    model_runner work inspect --project PATH --task TASK-ID --format json
    model_runner work execute --project PATH --task TASK-ID --operation-id ID \
      --expected-task-revision DIGEST --expected-project-identity ID \
      --expected-source-fingerprint DIGEST --execution-policy DIGEST \
      --timeout-seconds N --noninteractive --format json
    model_runner work status --project PATH --operation-id ID --format json
    model_runner work cancel --project PATH --operation-id ID --format json
    model_runner work recover --project PATH --format json

Reuse the interactive command’s configured model-backed Agent_Runner and existing Framework APIs. Persist the caller
operation ID before execution and bind it to project identity, task revision, generation, agent/invocation IDs, and
final report. Identical requests adopt the operation; mismatched reuse is an integrity error. Lookup survives restart.
Semantic conflict acceptance remains disabled noninteractively.

Status: **implemented and validated** in model_runner commit `a0522e83`. The adapter reuses the interactive route's
configured `Agent_Runner`, native workspaces, cancellation, recovery, integration, and code-health gates. A real local
model execution traversed the headless route; its invalid agent response was retained as a native failure. Repeating
the same operation returned the same generation and outcome without another model execution. Cross-process
cancellation and recovery also passed. The full suite ran 942 tests; the single initially reported release-gate
failure was a stale compiler diagnostic artifact, and the isolated release gate passed after the corrected unit was
rebuilt. The warnings-as-errors validation build passed.
