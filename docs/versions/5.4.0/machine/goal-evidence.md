# Goal completion evidence

Goal: research every Android page and control, build a control tree, convert it into E2E cases, reverse-engineer requirements with the a01 requirements layer, and prepare the HarmonyOS development work.

## Clause 1 — every Android page and control

| Evidence | Value |
| --- | --- |
| Research units | 11 |
| Android layouts covered | 18 of 18 under `mobile/src/main/res/layout` |
| Android menus covered | 9 of 9 under `mobile/src/main/res/menu` |
| Preference and shortcut XML covered | 3 of 3 under `mobile/src/main/res/xml` |
| UI Kotlin classes covered | 14 of 14 from `setContentView` and preference loading |
| Controls recorded | 340 |
| Controls with a source reference | 340 |
| Deterministic source-coverage check | PASS (check 10 of `tools/check-specs.mjs`) |
| Completeness critic | PASS, 0 uncovered areas |

## Clause 2 — control tree

| Artifact | Content |
| --- | --- |
| `android/units/U01.md` … `U11.md` | One control tree per unit, with type, label, visibility, enable rule, action, destination and source |
| `android/INDEX.md` | Unit index, 48 root screens and dialogs, parity summary |
| `machine/U01.json` … `U11.json` | Machine-readable control tree with parent links |

## Clause 3 — E2E cases

| Evidence | Value |
| --- | --- |
| Cases | 348 |
| Cases with preconditions, steps and expected results | 348 |
| Cases with a control path | 348 |
| Cases with a HarmonyOS parity tag | 348 |
| Cases per unit | 24 to 46 |
| Rule-to-case traceability | 412 of 412 rules covered, 0 rows marked `not covered` |
| Case documents | `e2e/U01.md` … `U11.md`, indexed by `e2e/INDEX.md` |

## Clause 4 — a01 requirements reverse-engineering

The requirement document follows the a01 requirements-layer contract (L-01-a) at the user's chosen scope.

| a01 requirement | Evidence in `requirements/requirements.md` |
| --- | --- |
| Users | `## Users`, two roles |
| Problem and outcome | `## Problem and outcome` |
| Scope and non-goals | `## Scope`, three lists |
| Requirement items table, first column is the ID | `## Requirement items`, 412 rows |
| Open items | `## Open items`, assumptions, fallback exits, parity ties, 3 example warnings |
| State and lifecycle with five columns | `## State and lifecycle`, 51 state machines |

The a01 requirements model (`requirements-model.json`) is built in the a01 batch and passes checks M1 to M9.

## Clause 5 — preparation for HarmonyOS development

| Parity value | Cases | Development meaning |
| --- | ---: | --- |
| implemented | 63 | Keep. Regression target. |
| partial | 93 | Finish. Each case names the limit. |
| missing | 136 | Build. Each case has steps and expected results. |
| android-only | 56 | Do not port. The case explains the platform dependency. |
| Total | 348 | The parity backlog for 5.4.0. |

## Verification

| Check | Result |
| --- | --- |
| 3 independent verifiers per unit, at least 2 pass | 11 of 11 units accepted |
| U01 extra repair and confirmation | 2 passes plus a clean confirmation pass |
| `node tools/check-specs.mjs` | PASS, 0 failures, 3 warnings |
| Requirement rows vs rules | 412 vs 412, no duplicates, no missing |
| Case IDs vs case index | 348 vs 348, no missing |
| Write boundary | Files written; no git add, commit or push |

## Clause 6 — HarmonyOS development

| Evidence | Value |
| --- | --- |
| Units implemented | 11 |
| Host specs | 500 passed, 0 failed |
| HAP build | Clean build, 0 errors, both ABIs, signed HAP produced |
| Rust core suites | 39 passed, 0 failed |
| Cases implemented | 224 |
| Cases partial | 52, each names the missing part |
| Cases missing | 0 |
| Android-only decisions | 72 |
| Device E2E | Emulator suites 5 of 5 passed; `VpnE2eTest` needs real hardware |

Evidence lives in `docs/changes/CHG-20261028-hos-parity/checks/`.
