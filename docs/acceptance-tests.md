# Acceptance Test Catalog

Each acceptance record names its fixture and cleanup so failures can be
reproduced without reusing hidden state. “Store” means the coordinator
database; “upstream” means the authoritative fixture or real application
state. Automated cases run from tests/src/quality_manager_test_suite.adb
unless another repository is named.

| ID | Fixture and setup | Operation | Expected store / upstream / diagnostic | Cleanup |
|---|---|---|---|---|
| AT-001 | qm_adapter_fixture, project 7 | Run assessment | Completed run 2; upstream contains violation/pass evidence; result is not an execution failure | Delete temp DB |
| AT-002 | Same assessment ingested twice | Save identical work identity twice | One work item; no second upstream task; success/idempotent | Delete temp DB |
| AT-003 | Project key with another database UUID | Read/attach evidence | No mutation; upstream untouched; qualified-identity mismatch | Delete temp DB |
| AT-004 | Completed assessment 2 with violation | Generate/reconcile Improve plan | Exact run, plan revision, task, and canonical finding set retained; replay creates no duplicate work | Delete temp DB |
| AT-005 | Plan without approval | Publication precondition evaluation | No dispatch; no native task; authorization required | Delete temp DB |
| AT-006 | Approval for revision 2, request revision 3 | Validate_Approval | Approval unchanged; no publication; authorization required | None |
| AT-007 | Existing logical remediation and publication mapping | Bind mapping twice | One active dispatch; one native identity; idempotent success | Delete temp DB |
| AT-008 | Ready TASK-001 fixture | Execute_Or_Reconcile | Attempt and committed journal; native execution observed; success | Delete temp DB |
| AT-009 | Non-ready native snapshot | Eligibility/dispatch evaluation | No attempt; no agent start; blocked reason | Delete temp DB |
| AT-010 | Two failed native attempts with restart before each retry | Reopen and execute through the third permitted attempt | Three durable sequence numbers and distinct derived operation IDs; no replay duplication | Delete temp DB and marker |
| AT-011 | Running native operation | Runner cancel | Cancellation response retained; upstream request bounded; interrupted outcome | None |
| AT-012 | Completed native task, Improve still failing | Verify remediation | Verification record is not successful; native state preserved; unresolved | Delete temp DB |
| AT-013 | Integrated task, fresh pass, explicit clean comparison | Verify remediation | Append-only verification becomes verified; exact upstream run used | Delete temp DB |
| AT-014 | Integrated task with new comparison regression | Verify remediation | Candidate rejected/not verified; regression evidence preserved | Delete temp DB |
| AT-015 | 32/33 or unknown indicator evidence | Decode/evaluate assessment | No successful verification; upstream evidence unchanged; incomplete | None |
| AT-016 | Policy fingerprint changed after planning | Freshness/approval validation | Dispatch remains unexecuted or intervention state; stale policy diagnostic | Delete temp DB |
| AT-017 | Two lease owners, same generation | Acquire coordinator/project lease | One fenced owner; no second upstream action; stale lease diagnostic | Delete temp DB |
| AT-018 | Attempt count reaches configured maximum | Persisted dispatch retry/finalization | Existing logical task fails or blocks; durable count survives restart; no fourth operation | Delete temp DB |
| AT-019 | Two campaign objectives, one global remediation | Find_Shared_Work | Both objectives reference one work item; one native task; success | Delete temp DB |
| AT-020 | Executing campaign then pause | Pause and scheduler dispatch | Campaign paused; existing attempt retained; no new dispatch | Delete temp DB |
| AT-021 | Campaign revision 2 after restart | Reopen/reconcile | Original target baseline rows retained; no upstream mutation | Delete temp DB |
| AT-022 | Every frozen target updated with newer pass | Reconcile campaign | Campaign Verified; upstream evidence read-only; completed | Delete temp DB |
| AT-023 | Qualified release then changed commit/source | Invalidate candidate | Release Superseded; prior bundle retained; invalidated | Delete DB and export |
| AT-024 | Applicable release gate below threshold | Evaluate release | Candidate not verified; no publication; negative result | Delete DB and export |
| AT-025 | Failing exact candidate, exact approval, maintenance adapters, then fresh 33-pass evidence | Qualify with remediation | Native work integrated, generation incremented, candidate Verified, canonical evidence saved | Delete DB, workspaces, markers, and export |
| AT-026 | Exported canonical bundle | Reassemble chunks and recompute bundle digest | Store unchanged; exported bytes match digest; integrity success | Delete DB and export |
| AT-027 | Improve publication journal interrupted | Recover publication/adopt mapping | Existing mapping retained; no duplicate task; reconciled | Delete temp DB |
| AT-028 | Repeat coordinator recovery | Reconstruct/reconcile twice | Same terminal state and attempt count; no repeated upstream action | Delete temp DB |
| AT-029 | unknown-schema.json | Parse adapter response | No mutation; upstream read only; incompatible contract | None |
| AT-030 | Corrupt serialized coordinator row | Open/read store | No silent rewrite; no upstream action; integrity failure | Delete corrupt fixture |

## Real-system evidence

Phase 0 used real pinned Ada Quality and Improve repositories to create a
completed assessment and PLAN-000001. Model Runner commit a0522e83 includes
the required real-model noninteractive exercise and proves that replay does not
invoke inference twice. Final multi-project maintenance, campaign, and release
qualification runs remain release-gate activities: they require configured
real project inventory, current authorization records, and model credentials.
Simulated adapter results are not accepted as substitutes for those three
records. The only local Ada Quality inventory found during stabilization was a
legacy schema-3 database whose supported migration rejected a noncanonical
measurement; its original bytes were restored. Real-system execution therefore
requires a valid schema-6 inventory rather than an unsupported repair of that
historical database.
