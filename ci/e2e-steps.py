#!/usr/bin/env python3
"""Write the a01 E2E run log from an `aa test` transcript.

The on-device driver (`ci/hos-emulator-e2e.sh`) calls this at the end of a run.
hypium prints one block per test; this reads those blocks and writes the
`e2e-steps.json` contract that `scripts/e2e-report.py` consumes.

Every case is one on-device test. Each case has one terminal-evidence step:
the emulator has no UI to drive, so the transcript is the evidence.
"""
import argparse
import json
import re
import sys

CLASS_RE = re.compile(r"OHOS_REPORT_STATUS: class=(\S+)")
TEST_RE = re.compile(r"OHOS_REPORT_STATUS: test=(.*)$")
CODE_RE = re.compile(r"OHOS_REPORT_STATUS_CODE: (-?\d+)")
SUM_RE = re.compile(r"OHOS_REPORT_RESULT: stream=Tests run: (\d+), Failure: (\d+), "
                    r"Error: (\d+), Pass: (\d+), Ignore: (\d+)")


def parse(path):
    """Return (cases, summary) from the transcript."""
    cases = {}
    current_class = ""
    current_test = ""
    summary = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            match = CLASS_RE.match(line)
            if match:
                current_class = match.group(1)
                continue
            match = TEST_RE.match(line)
            if match:
                current_test = match.group(1).strip()
                key = (current_class, current_test)
                if key not in cases:
                    cases[key] = {"class": current_class, "name": current_test, "code": None}
                continue
            match = CODE_RE.match(line)
            if match and current_test:
                key = (current_class, current_test)
                # The first code announces the start; the last one is the result.
                cases[key]["code"] = int(match.group(1))
                continue
            match = SUM_RE.search(line)
            if match:
                summary = {
                    "run": int(match.group(1)),
                    "failure": int(match.group(2)),
                    "error": int(match.group(3)),
                    "pass": int(match.group(4)),
                    "ignore": int(match.group(5)),
                }
    ordered = list(cases.values())
    for index, case in enumerate(ordered, start=1):
        case["id"] = "E2E-DEVICE-%02d" % index
    return ordered, summary


def build(cases, summary, args):
    out_cases = []
    for case in cases:
        # hypium prints code 0 for a passed spec and a non-zero code otherwise.
        ok = case["code"] == 0
        status = "pass" if ok else "fail"
        output = "class=%s\ntest=%s\nstatus_code=%s" % (case["class"], case["name"], case["code"])
        out_cases.append({
            "id": case["id"],
            "title": case["name"],
            "oracle_ids": ["O-JOURNEY-01"],
            "status": status,
            "steps": [{
                "id": "S-01",
                "name": "Run on the emulator",
                "operation": "aa test -s class %s on the running emulator." % case["class"],
                "expected": ["The test passes."],
                "actual": "Pass." if ok else "The test failed.",
                "status": status,
                "evidence": {"kind": "terminal", "output": output},
            }],
        })
    doc = {
        "skill_version": "a01",
        "title": args.title,
        "change_id": args.change_id,
        "baseline": args.baseline,
        "environment": args.environment,
        "command": args.command,
        "executed_at": args.executed_at,
        "target": "mobile",
        "cases": out_cases,
    }
    if summary is not None:
        doc["notice"] = ("Tests run: %d, Failure: %d, Error: %d, Pass: %d, Ignore: %d."
                         % (summary["run"], summary["failure"], summary["error"],
                            summary["pass"], summary["ignore"]))
    return doc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--aa-log", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--change-id", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--command", required=True)
    parser.add_argument("--executed-at", required=True)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--title", default="HarmonyOS on-device E2E")
    args = parser.parse_args()

    cases, summary = parse(args.aa_log)
    if not cases:
        print("no test cases found in %s" % args.aa_log, file=sys.stderr)
        return 2
    doc = build(cases, summary, args)
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("wrote %s: %d cases" % (args.output, len(doc["cases"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
