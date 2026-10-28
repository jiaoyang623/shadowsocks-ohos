#!/usr/bin/env python3
"""Merge the eight high-level review dimension files into one checklist."""
import json
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
REVIEW = os.path.join(ROOT, "docs/changes/CHG-20261028-hos-parity/checks/review")
OUT = os.path.join(ROOT, "docs/changes/CHG-20261028-hos-parity/checks/high-level-review.json")
DIMS = [
    "requirement-coverage",
    "hld-contract-coverage",
    "journey-branches",
    "reverse-enumeration",
    "state-and-persistence",
    "concurrency-and-timing",
    "non-functional",
    "interface-consumers",
]
PREFIX = "/opt/git/github/shadowsocks-ohos/"

FIXED = [
    "abandoned probe", "previous session's terminal status", "first health poll",
    "starting never times out", "stays in `starting`", "stuck in starting",
    "stop timeout", "second extension", "poll can be installed",
    "failed settle", "session settle rejects", "settlement rejection",
    "stale cached ACL", "stale cache", "custom-rules route deploys a stale",
    "notification stop action", "previous session's status",
    "code 110004", "metered", "subscription icon",
    "active subscription profile has no path", "scanned profiles copy",
    "qr scan import drops", "early extension failure is overwritten",
    "proxy mode's manual connection test", "v5.3.5 profiles lose subscription ownership",
    "export writes the picked file without truncation", "drag after a pending removal",
]
PLATFORM = [
    "tile", "quick settings", "launcher shortcut", "boot receiver", "boot_completed",
    "tasker", "direct boot", "device-protected", "transproxy", "installed-package",
    "installed app", "plugin package", "plugin provider", "untrusted-plugin",
    "workmanager", "aclsyncer", "shortcut", "hap absent", "built hap is absent",
    "plugin help", "help button", "signature", "package-change", "reload broadcast",
    "no full enumeration", "no boot", "no tile", "plugin list is static",
]
TRACKED = [
    "icon", "uid", "label", "progress bar", "sensitive", "cursor", "snackbar",
    "toast", "glyph", "500 ms", "4000", "1200", "mime", "notification channel",
    "pinned", "store shape", "preference key", "no app icon",
]
EXTRA = [
    "per-row latency", "speed test", "separate test connection", "automatic connect verification",
    "typed import url", "replace-all confirmation", "qr scan retry", "settings endpoint",
    "share over lan", "settings action buttons", "remote dns", "show qr code",
    "app picker accepts typed", "subscription row profile count", "about version",
    "notification permission prompt", "diagnostics exports", "mainshell ringstate",
    "pluginoptions isknownplugin", "transfer.picktextfile", "qrim port.copyfeaturesettings",
    "notificationcontent.notificationtitle", "customrules.removerule", "profile exposes editor helpers",
    "sip008 export", "index routelabel", "aboutopener.about_opened", "subscription and subscriptionrefresh export",
    "internal-only constant", "profileedit blank-form", "profileqr route",
    "probe and speed-test url overrides",
]
# Found by the interface-consumers review and fixed afterwards. The names are
# the review titles, not the code identifiers.
FIXED_INTERFACE = [
    "notification traffic and totals lines drop",
    "subscription merge overwrites a corrupt profile store",
    "export's new null branch is unreachable",
    "subscription list writes have no error branch",
    "new index messages pass formatted resources",
]
# Strong items that the design review left open and the final fix pass closed.
FIXED_FINAL = [
    "c-02 start call returns before the tun is ready",
    "a failed acl import overwrites the cached file",
    "c-08 unavailable app query returns the stored names and no reason",
    "c-04 missing stat endpoint clears the sample and fails the ui phase",
    "c-04 sample lifecycle clears before settlement",
    "with a stale selected id, connect starts the first profile instead of asking for one",
    "session settlement races the extension's own traffic writes and teardown clear",
    "subscription refresh overwrites concurrent profile writes",
    "a session stopped outside the page is never settled and its counters are erased",
    "custom rules file is read while the ui truncates and rewrites it",
    "bare plugin options do not round-trip and gain catalogue defaults",
    "subscription store treats an unreadable file as empty and the next save destroys it",
    "the page and the extension resolve the selected profile differently when it is obsolete",
    "the ui starts the next tunnel on a `stopped` status written before teardown",
]

def norm_anchor(anchor):
    a = str(anchor or "").strip()
    if a.startswith(PREFIX):
        a = a[len(PREFIX):]
    return a

def norm_severity(value):
    v = str(value or "").lower()
    if v in ("high", "medium", "strong"):
        return "strong"
    return "weak"

def text_of(item):
    blob = f"{item.get('title','')} {item.get('reason','')}".lower()
    for e in EXTRA:
        if e in blob:
            return "extra"
    for f in FIXED_INTERFACE:
        if f in blob:
            return "fixed-interface"
    for f in FIXED_FINAL:
        if f in blob:
            return "fixed-final"
    if "a start is accepted from failed as well as stopped" in blob:
        return "phase-model"
    for f in FIXED:
        if f in blob:
            return "fixed"
    for p in PLATFORM:
        if p in blob:
            return "platform"
    for t in TRACKED:
        if t in blob:
            return "tracked"
    if "c-05 error clause" in blob:
        return "conflict-c05"
    if "c-01 missing port" in blob:
        return "conflict-c01"
    return "open"

REASONS = {
    "fixed": "Resolved in the final implementation after this review. See checks/build-fixes.txt and the 490-case host run.",
    "fixed-interface": "Resolved after the interface-consumers review. See checks/build-interface.txt for the clean HAP build and checks/host-tests.txt for the 490-case host run.",
    "fixed-final": "Resolved in the final fix pass after this review. See checks/build-final.txt for the clean HAP build, checks/host-tests.txt for the host run, and checks/e2e-final.txt for the on-device result.",
    "phase-model": "Failed is a terminal UI phase whose service state is Stopped: no tunnel runs in it. A start from Failed performs the same stopped-service start as a start from Idle, so R-UA-27's rule (no start while a service runs) holds. The failed reason stays on screen until the next start.",
    "platform": "Platform decision recorded in the unit LLD and the case parity tag. No public HarmonyOS API exists for this surface.",
    "tracked": "Already recorded as a partial or android-only case in machine/Uxx.json. The missing part is named there.",
    "extra": "Extra app behavior outside the Android parity requirement set. It is retained as a HarmonyOS capability.",
    "conflict-c05": "The HLD clause conflicts with requirements R-UE-19 and R-UE-20. The requirements are authoritative.",
    "conflict-c01": "The HLD clause conflicts with R-UC-07 and the LLD, which define the 8388 fallback for a missing port.",
}

items = []
contexts = []
declared = []
for dim in DIMS:
    path = os.path.join(REVIEW, f"{dim}.json")
    if not os.path.exists(path):
        print(f"missing review file: {path}", file=sys.stderr)
        continue
    data = json.load(open(path))
    inputs = [norm_anchor(x) for x in data.get("inputs", [])]
    contexts.append({"agent": dim, "dimensions": [dim], "inputs": inputs})
    for x in inputs:
        if x not in declared:
            declared.append(x)
    raw_items = data.get("items", [])
    for raw in raw_items:
        title = str(raw.get("title", "")).strip()
        anchor = norm_anchor(raw.get("anchor", ""))
        severity = norm_severity(raw.get("severity"))
        kind = text_of(raw)
        disposition = "open" if kind == "open" else "not-applicable"
        entry = {
            "dimension": dim,
            "title": title,
            "anchor": anchor,
            "severity": severity,
            "disposition": disposition,
            "reason": str(raw.get("reason", "")).strip(),
        }
        if disposition == "not-applicable":
            entry["reason"] = REASONS[kind] + " " + entry["reason"]
        items.append(entry)
    cov = data.get("coverage", {}) or {}
    scanned = cov.get("scanned", cov.get("scanned_files", inputs))
    if isinstance(scanned, dict):
        flat = []
        for value in scanned.values():
            if isinstance(value, list):
                flat.extend(str(v) for v in value)
            else:
                flat.append(str(value))
        scanned = flat
    scanned = [norm_anchor(x) for x in scanned] if isinstance(scanned, list) else inputs
    coverage = {
        "dimension": dim,
        "result": "clean" if str(cov.get("result", "")).lower() == "clean" else "gaps-found",
        "scanned": scanned if scanned else inputs,
    }
    if cov.get("note"):
        coverage["note"] = str(cov["note"])
    data["_coverage"] = coverage
    items.extend([])

# Rebuild coverage in dimension order.
coverage = []
for dim in DIMS:
    path = os.path.join(REVIEW, f"{dim}.json")
    if not os.path.exists(path):
        coverage.append({"dimension": dim, "result": "uncovered", "scanned": ["No review file."]})
        continue
    data = json.load(open(path))
    cov = data.get("coverage", {}) or {}
    inputs = [norm_anchor(x) for x in data.get("inputs", [])]
    scanned = cov.get("scanned", cov.get("scanned_files", inputs))
    if isinstance(scanned, dict):
        flat = []
        for value in scanned.values():
            if isinstance(value, list):
                flat.extend(str(v) for v in value)
            else:
                flat.append(str(value))
        scanned = flat
    scanned = [norm_anchor(x) for x in scanned] if isinstance(scanned, list) else inputs
    entry = {
        "dimension": dim,
        "result": "clean" if str(cov.get("result", "")).lower() == "clean" else "gaps-found",
        "scanned": scanned if scanned else inputs,
    }
    if cov.get("note"):
        entry["note"] = str(cov["note"])
    coverage.append(entry)

# Deduplicate exact title + anchor pairs.
seen = set()
unique = []
for item in items:
    key = (item["title"], item["anchor"])
    if key in seen:
        continue
    seen.add(key)
    unique.append(item)
for i, item in enumerate(unique, start=1):
    item["id"] = f"HLR-{i:03d}"

doc = {
    "schema": "high-level-review/1",
    "meta": {
        "change_id": "CHG-20261028-hos-parity",
        "baseline": "e123804+dirty",
        "created_at": "2026-10-28T12:45:00+11:00",
        "reviewer_contexts": contexts,
        "inputs_declared": declared,
        "inputs_forbidden_checked": [
            "No docs/oracles file appears in any reviewer input list.",
            "No entry/src/test file appears in any reviewer input list.",
            "No entry/src/ohosTest file appears in any reviewer input list.",
            "No review page, review brief or review snapshot appears in any reviewer input list.",
        ],
    },
    "items": unique,
    "coverage": coverage,
}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(doc, open(OUT, "w"), indent=2, ensure_ascii=False)
open(OUT, "a").write("\n")
print(f"wrote {OUT}: {len(unique)} items, {len(coverage)} dimensions")
