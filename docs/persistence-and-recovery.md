# Persistence and Recovery

The coordinator maps the specification’s fourteen logical record kinds onto one native Database typed table. Each row
has a generated physical identity, globally unique logical key, record kind, normalized state, typed JSON payload,
terminal marker, and fencing generation. Secondary indexes cover logical key, record kind, and state. The strongly
typed facade currently owns the records needed by the first remediation loop; later workflows use the same envelope
without changing its physical schema.

Schema metadata contains a durable installation UUID. Opening an existing store validates that identity and the exact
schema version. A newer schema is a compatibility error; unknown or corrupt files are rejected without repair.

Work transitions are compare-and-set operations. The new work state and append-only event commit in one database
transaction. Terminal work cannot be reopened. Active dispatches use the global remediation identity as their unique
logical key, preventing duplicate physical execution across workflows.

Mutable project, campaign, target, and release records advance their fencing generation only when content changes.
Replaying identical current state is a no-op, so recovery does not manufacture a new generation.

External operations follow a durable journal:

| Persisted state | Restart action |
| --- | --- |
| Prepared | Revalidate, then invoke |
| Invoking | Query the external operation identity |
| Reconciling | Adopt the confirmed result |
| Committed | No action |
| Aborted | Preserve failure evidence |
| Needs intervention | Escalate without retry |

Recovery scanning is bounded. Lease acquisition and renewal require the caller’s observed generation and a strictly
larger new generation, so an obsolete owner cannot renew after another owner advances the fence.
Ada Quality assessments are treated as non-idempotent after invocation: a committed run is adopted by exact run ID,
while a crash with no durable run identity moves the journal to Needs intervention instead of repeating the check.
Exit code 3 is not an ambiguous crash when its versioned JSON contains a completed assessment. The coordinator adopts
that run identity, commits the journal, and separately records the evidence as incomplete and therefore inconclusive.
Improve plan generation is bound to an explicit assessment run. Improve's deterministic storage returns the existing
plan for the same exact evidence, so replay from `Invoking` is idempotent; reconciliation reloads the recorded plan ID
and revision before recreating any missing approval-gated coordinator work.
