# Required Upstream Changes

## AQ-ID-01 — Durable Ada Quality database identity

Add an installation UUID or durable identity to Ada Quality metadata and expose it through Ada_Quality.Reporting and
coordinator-facing JSON envelopes. It must survive relocation and backup restore, while database replacement at the
same path remains detectable. Add migration, import, and replacement tests.

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
    model_runner work execute --request FILE --format json
    model_runner work status --project PATH --operation-id ID --format json
    model_runner work cancel --project PATH --operation-id ID --format json
    model_runner work recover --project PATH --format json

Reuse the interactive command’s configured model-backed Agent_Runner and existing Framework APIs. Persist the caller
operation ID before execution and bind it to project identity, task revision, generation, agent/invocation IDs, and
final report. Identical requests adopt the operation; mismatched reuse is an integrity error. Lookup survives restart.
Semantic conflict acceptance remains disabled noninteractively.
