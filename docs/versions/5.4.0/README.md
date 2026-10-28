# Version 5.4.0 — Android parity

This version aligns the HarmonyOS app with the Android app.

## Baseline

| Item | Value |
| --- | --- |
| Android source | shadowsocks-android, tag v5.3.5-nightly, commit ae28fd9 |
| HarmonyOS source | shadowsocks-ohos 5.3.5, commit e123804 |
| Scope | Android `mobile` module, all pages and controls |
| Status | Implemented, host-verified and emulator-verified. `VpnE2eTest` needs real hardware; the four human gates and the result gate are pending. See `docs/changes/CHG-20261028-hos-parity/completion.md`. |
| Output size | 340 controls, 412 rules, 86 flows, 51 states, 348 cases |
| Parity after 5.4.0 | 224 implemented, 52 partial, 0 missing, 72 android-only |

## Purpose

The HarmonyOS app is a separate code base. Android changes do not reach it automatically.
This directory holds the verified description of the Android mobile UI.
It gives the port a fixed target.

The output has three layers:

1. A control tree for every page, dialog, menu and preference screen.
2. A requirement set in the a01 requirements-layer form.
3. E2E cases that turn the control tree into checks.

Each requirement and each case carries a HarmonyOS parity tag.

## Artifact map

| Path | Content |
| --- | --- |
| `context/meta.json` | Version metadata, users, problem, outcome, scope, assumptions |
| `context/unit-map.md` | The 11 research units and their Android files |
| `context/android-inventory.md` | Android feature inventory |
| `context/harmonyos-inventory.md` | HarmonyOS feature inventory and parity reference |
| `machine/U01.json` … `U11.json` | Machine-readable control tree, rules, states, flows, cases |
| `android/units/U01.md` … `U11.md` | Control tree and behavior rules per unit |
| `android/INDEX.md` | Control tree index |
| `e2e/U01.md` … `U11.md` | E2E cases per unit |
| `e2e/INDEX.md` | Case index and parity view |
| `requirements/requirements.md` | Requirement document in the a01 requirements-layer form |
| `tools/check-specs.mjs` | Deterministic validator for the machine specs |

## Method

The research runs as one dynamic workflow over a fixed list of 11 units.
Each unit gets one extraction agent.
Three independent verifiers check each unit with different lenses: control coverage, behavior accuracy, state and edge coverage.
A unit is accepted when at least two verifiers pass.
A failed unit gets one repair round and a second vote.
U01 received two repair rounds and a final confirmation pass.
A completeness critic checks the whole set against the Android resource directories.
A synthesis pass writes the requirement document and the two indexes.
The deterministic spec validator (`tools/check-specs.mjs`) is the release gate.
The current set passes with 0 failures and 3 warnings.

## Parity values

| Value | Meaning |
| --- | --- |
| `implemented` | The HarmonyOS app has the behavior. |
| `partial` | The behavior exists with a known limit. |
| `missing` | The behavior does not exist. |
| `android-only` | The behavior depends on an Android platform surface and cannot be ported as-is. |

## Reading order

1. `requirements/requirements.md` for the requirement set and the open items.
2. `android/INDEX.md` for the control tree.
3. `e2e/INDEX.md` for the case set and the parity view.
4. `android/units/` and `e2e/` for one unit of detail.
