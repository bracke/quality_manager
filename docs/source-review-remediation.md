# Source Review Remediation

This record closes the seven findings from the 23 November 2026 source-level review of commit `51c9d51`. Each
correction is independently exercised by AUnit and remains subject to the normal release gate.

## F-01 — Clean reproducible builds

`Quality_Manager.Reproducibility` prepares two independent source-only workspaces. Release validation builds each
workspace once, requires generated artifacts, and compares canonical path-and-SHA-256 manifests. The fixture can
emit workspace-dependent artifacts and qualification rejects them.

## F-02 — Durable execution attempts

Attempt records now carry a positive sequence number. Native operation identities are derived from the dispatch and
attempt number, validated when read, and retained across restart. The dispatcher requeues a failed execution only
within the configured budget. A three-attempt test restarts the store twice and observes three distinct operations.

## F-03 — Final source identity

Local checks capture an authored-source manifest before execution and recompute it afterward. They also recheck
`HEAD` and tracked-tree cleanliness. Qualification then obtains a second authoritative assessment. A successful test
command that edits an Ada body is rejected.

## F-04 — Explicit proof evidence

Applicable proof selects the project explicitly and runs GNATprove in prove mode at level 2 with checks and warnings
as errors. Qualification requires a bounded report containing the expected analyzed-unit and proved-obligation
summary; a zero exit without that evidence fails.

## F-05 — Non-mutating dry-run

Maintenance dry-run skips leases, recovery, project observations, cycles, work, and upstream mutation. Tests compare
a digest of every logical record before and after matched and unmatched dry-runs.

## F-06 — Release remediation loop

Configured non-dry qualification now uses the shared authorized maintenance dispatcher. A failing candidate may be
planned, published, executed, integrated, reassessed, promoted to a new immutable generation, and requalified until
its budget is exhausted. Missing approval remains a blocking result. The end-to-end fixture proves both paths.

## F-07 — Assessment-only recovery

Abbreviated assessment recovery is accepted only for the reserved `__assessment__` work shape with no Improve
identity. Published remediation work must pass the complete native, Improve, regression, and freshness predicate.

Release requires `alr test`, forced validation, applicable GNATprove, GNATdoc, and at least 90% complete production
line coverage. No finding changes authorization policy or permits a coding agent to certify its own result.
