# Phase 0 Compatibility Matrix

Frozen inspection point: 2026-11-21. HEAD identifies source; “dirty” means local changes existed outside that
immutable revision.

| Component | Version | HEAD | Worktree | Use | Status |
| --- | --- | --- | --- | --- | --- |
| ada_quality | 0.1.0 | fe7c074aadbdc90e9cf3338987237164c9c31786 | clean | measurement/JSON | AQ-ID-01 |
| ada_quality_summary | 0.1.0 | 3995d7186387160a3d40513586f554e1ae1403b4 | clean | portfolio JSON | AQS-PAGE-01 |
| improve | 0.1.0 | 3e6513daa5ab38f5f12cd985516ce758fe0ff7d1 | clean | planning/verification CLI | IMP-APPROVE-01 |
| model_runner | 0.1.0-dev | 67b7e8bdbfc2e2e800ec4b8e907701fd5294b848 | dirty | native work | MR-HEADLESS-01 |
| database | 0.14.0 | 22c106420122f52226a4e1711f075442479881cd | inspected | persistence | compatible |
| hostkit | 0.2.0-dev | 2e31558d0fef1d4f7e06ad13fa40bddaa1998bcf | inspected | processes | wrapper needed |
| jsonlib | 0.1.0-dev | 24a1b18a7be19bb65725d8114c4f069658ced614 | inspected | JSON | compatible |
| config | 0.1.0-dev | 58448029995b977a052df40ab72ce6be1b18bb7e | inspected | configuration | compatible |
| cryptolib | 0.1.0-dev | 2e5c415f65fd49c2a496c97813740fa9b83e02fa | inspected | hashes/signatures | compatible |
| versionlib | 0.1.0-dev | 71c02ed2f6b6c4fa693715e6306fa2eb98b79fec | inspected | Git | compatible |

Post-freeze contract implementation: Ada Quality commit `3a85a5b` implements AQ-ID-01 with logical schema version 6
and `database-statistics` JSON schema version 2. The frozen inspection row above remains the provenance baseline.

## Contract checks

Version/help probes passed for all four applications. A real Ada Quality fixture produced assessment-v1 evidence and
Summary problems/regressions version-1 documents.

Full upstream test actions were attempted:

- ada_quality: the current test action cannot run i18n's missing generated pre-build executable.
- ada_quality_summary: its test action is blocked by the same i18n pre-build failure; an earlier attempt also found
  its aqs_writer incompatible with the new Ada Quality storage surface.
- improve: its direct test action lacked the Alire project path; an Alire build then reached linking but failed on
  missing generated i18n runtime symbols.

These are upstream blockers, not coordinator passes. Every missing cross-repository operation has an explicit work
item, but Phase 4 and autonomous writes must not be represented as available until their gaps pass tests.

AQ-ID-01 was subsequently validated with Ada Quality's warnings-as-errors build, 59/59 tests, release checker,
GNATdoc generation, and refreshed production coverage of 90.03%. A real schema-6 database then supplied a durable
identity to the coordinator adapter and assessment 1 for `quality_manager`; Improve stored `PLAN-000001` revision 1
from that exact database-qualified assessment.
