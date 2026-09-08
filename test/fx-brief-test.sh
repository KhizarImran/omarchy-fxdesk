#!/usr/bin/env bash
# Offline check for bin/fx-brief: the filtering, the sorting, and the shape of
# the session windows. The calendar is a fixture written for today, so the
# "today only" rule stays under test on every day it runs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export FX_BRIEF_CACHE="$tmp/thisweek.json"

python3 - "$FX_BRIEF_CACHE" <<'PY'
import json, sys
from datetime import datetime, timedelta

local = datetime.now().astimezone()
def at(hour, day=0):
    return (local.replace(hour=hour, minute=0, second=0, microsecond=0)
            + timedelta(days=day)).isoformat()

json.dump([
    {"title": "Late USD print",  "country": "USD", "date": at(21), "impact": "High",   "forecast": "1%", "previous": "2%"},
    {"title": "Early USD print", "country": "USD", "date": at(3),  "impact": "High",   "forecast": "",   "previous": ""},
    {"title": "EUR medium",      "country": "EUR", "date": at(9),  "impact": "Medium", "forecast": "",   "previous": ""},
    {"title": "GBP noise",       "country": "GBP", "date": at(10), "impact": "Low",    "forecast": "",   "previous": ""},
    {"title": "CNY excluded",    "country": "CNY", "date": at(11), "impact": "High",   "forecast": "",   "previous": ""},
    {"title": "Tomorrow",        "country": "USD", "date": at(9, 1), "impact": "High", "forecast": "",   "previous": ""},
], open(sys.argv[1], "w"))
PY

out="$("$here/../bin/fx-brief" --ccy USD,EUR --impact High,Medium --max-age 99999)"

python3 - <<PY
import json, sys
from datetime import datetime
from zoneinfo import ZoneInfo

brief = json.loads('''$out''')
fail = []

titles = [e["title"] for e in brief["events"]]
if titles != ["Early USD print", "EUR medium", "Late USD print"]:
    fail.append("wrong events or wrong order: %s" % titles)
if brief["error"]:
    fail.append("unexpected error: %s" % brief["error"])

codes = [s["code"] for s in brief["sessions"]]
if codes != ["SYD", "TKY", "LDN", "NY"]:
    fail.append("wrong sessions: %s" % codes)

for session in brief["sessions"]:
    if not session["windows"]:
        fail.append("%s has no windows" % session["code"])
    for window in session["windows"]:
        if window["close"] <= window["open"]:
            fail.append("%s closes before it opens" % session["code"])
        # A weekday in the centre's own clock, not ours: Monday in Sydney is
        # still Sunday in London, and that window is a real one.
        opened = datetime.fromtimestamp(window["open"], ZoneInfo(session["tz"]))
        if opened.weekday() >= 5:
            fail.append("%s has a weekend window" % session["code"])

if fail:
    print("\n".join("FAIL: " + f for f in fail))
    sys.exit(1)
print("ok: %d events, %d sessions" % (len(brief["events"]), len(brief["sessions"])))
PY
