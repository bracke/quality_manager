# Phase 0 Integration Contracts

Validated from source, schemas, executable help, and generated fixtures on 2026-11-21. Recorded revisions are in
[compatibility-matrix.md](compatibility-matrix.md). A dirty upstream worktree is not a released contract.

## Ada Quality

Supported surfaces are the public Ada_Quality.Reporting API and versioned CLI JSON:

| Coordinator operation | Confirmed contract |
| --- | --- |
| List projects | project list --format json; project-list-v1 |
| Inspect evidence | assessment show RUN --format json; assessment-v1 |
| Plan a check | check --project ID --profile NAME --dry-run --json; check-plan-v1 |
| Run a check | check --project ID --profile NAME --json |
| Compare exact runs | assessment diff BASE CURRENT --format json; assessment-comparison-v1 |
| Diagnose | doctor --project ID --json |

Assessment JSON binds project/run IDs, path, source, policy, toolchain, terminal status, all 33 results, and
executions. Exit 0 means complete/pass, 1 complete/violations, 2 invalid request, 3 incomplete evidence, and 4
database/integrity failure. JSON, not exit status or terminal prose, is authoritative.

Gap **AQ-ID-01**: no stable database installation identity is exposed. Snapshot_Identity changes with contents and a
canonical path does not detect replacement. Coordinator writes remain disabled until Ada Quality exposes a durable
database UUID/fingerprint through reporting and JSON.

## Ada Quality Summary

The noninteractive CLI exposes summary, projects, project, indicators, indicator, problems, waivers, regressions,
compare, trends, and history. JSON envelope version 1 preserves passing, violations, incomplete, and unassessed.
Exit 0 means a report rendered, even with violations; only explicit --fail-on produces exit 1.

Reports are read-only scheduling advice. compare BASE CURRENT preserves exact assessment selection and reports
incompatibility instead of substituting a baseline.

Gap **AQS-PAGE-01**: the CLI supports --limit but no cursor or offset. Complete enumeration requires a cursor contract
or a proven configured maximum above every possible result set.

## Improve

Improve declares its CLI and versioned JSON as the external contract. Confirmed commands are:

    plan --project PROJECT
    plan show PLAN-ID [--revision N]
    plan approve PLAN-ID
    apply PLAN-ID [--task IMP-ID] [--dry-run]
    tasks [--project PROJECT|--task IMP-ID] [--revision N]
    verify (--task IMP-ID|--project PROJECT) [--revision N] [--run RUN]
    recover
    audit PLAN-ID [--revision N] --format json

JSON envelope version 2 and stable IMP-E-* diagnostics are authoritative. Publication is approval-gated, journaled,
provenance-qualified, and adopts matching native tasks. Verification keeps native state separate from quality.

Gap **IMP-APPROVE-01**: the CLI approves only the latest revision and accepts neither an expected revision nor a
complete content digest. Autonomous approval is disabled until an atomic
plan approve PLAN-ID --revision N --content-sha256 DIGEST contract exists and returns the bound digest.

## model_runner

The public framework confirms Tasks.Ready, Tasks.Effective, Work.Plan_For, Work.Execute, Work.Take_In, Work.Cancel,
Work.Recover, and Work.Audit. Execute preserves permission, workspace, code-health, lifecycle, and completion gates.
Interactive /work supplies the configured model-backed Agent_Runner.

Gap **MR-HEADLESS-01**: the executable has no work command, durable coordinator operation ID, JSON schema, or restart
lookup. Phase 4 must wrap the existing runner and framework. Repeating one operation ID must never start a second run.

## Shared libraries

- database 0.14.0: typed schemas, transactions, indexes, WAL recovery, process locking.
- hostkit 0.2.0-dev: vector process invocation, child directory, deadlines, cancellation, and termination.
- jsonlib 0.1.0-dev: strict RFC 8259 parsing/rendering.
- config/config_runtime 0.1.0-dev: bounded typed TOML/environment sources with provenance and redaction.
- cryptolib 0.1.0-dev: streaming SHA-256 and signing.
- versionlib 0.1.0-dev: Git-compatible repository operations.

The coordinator process adapter must add streaming byte limits and an environment allowlist over Hostkit. It must
never construct a shell command.
