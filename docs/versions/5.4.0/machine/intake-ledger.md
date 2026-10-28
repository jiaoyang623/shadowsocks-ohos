# Intake ledger — Android parity research

## Verified facts

| Fact | Source |
| --- | --- |
| Android baseline is shadowsocks-android tag v5.3.5-nightly, commit ae28fd9 | `git log` and `buildSrc/src/main/kotlin/Helpers.kt` |
| Android mobile module has 18 layouts, 9 menus, 3 preference/shortcut XML files | `mobile/src/main/res` listing |
| 14 Kotlin classes inflate a view or drive a screen | `grep setContentView/addPreferencesFromResource` |
| HarmonyOS baseline is 5.3.5, commit e123804 | `AppScope/app.json5`, `git log` |
| The repository documents are in English | `AGENTS.md` |
| a01 requirements layer needs Users, Problem and outcome, Requirement items, Open items, and a five-column state table | `~/.claude/skills/a01/references/design/requirements.md` |
| The docs directory is owned by w2h; the version directory was created and owns by red for writing | `ls -ld`, `sudo -u w2h` check |

## User decisions

| Decision | Value |
| --- | --- |
| E2E case form | Markdown |
| Coverage | All mobile pages and controls; TV and plugin modules excluded |
| Verification | 3 independent agents per unit; at least 2 passes |
| Token budget | No limit; fixed scale |
| Version directory | `docs/versions/5.4.0/` |
| a01 integration | Requirements-layer contract only; no model, no full batch |
| Write boundary | Write files; no git add, commit, or push |
| Document language | English |
| Control tree layout | One file per unit plus an index |
| HarmonyOS parity | Tag every case with implemented, partial, missing, or android-only |
| Execution | Compile and run without a second confirmation stop |

## Open items at intake

None. All later open items are recorded in `requirements/requirements.md`.
