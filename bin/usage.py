#!/usr/bin/env python3
"""How much allowance each build runner has left: one line per runner. Read-only; never blocks a build.

    python3 -I usage.py      (python -I usage.py on Windows)

Runners and where each one is read from. Every source is optional: a source that is missing, slow
or failing makes its runners "unknown", never "low".
    claude, codex, cursor   quota-cli (`cargo install quota-cli`), which reads each CLI's stored login
                            read-only and never refreshes it
    agy-gemini, agy-claude  Hermes: `hermes usage --provider antigravity-subscription-directsdk --json`
                            (agy-gemini is what Gemini Carbon and Hydrogen use; agy-claude is the Claude
                            and GPT models agy offers)

A runner is LOW when any of its windows has USAGE_LOW_PCT percent or less left.

It always exits 0 and never prints a traceback. Every outside call has a deadline, so the whole check
ends in about 80 seconds at the very most (usually 10): the quota side tries the optional QUOTA_WATCH
helper for up to 40 seconds and then quota-cli for up to 40, while the agy side waits up to 60 for
Hermes; the two sides run at the same time. It writes nothing, not even a Python cache file.
Anything a tool says that looks like an email address, a login token or a home folder is hidden.

Settings come from the environment, or from local.env next to SKILL.md (git ignores that file; save it
as UTF-8 or as PowerShell's UTF-16). A leading ~ or %VAR% in a path is expanded.
    USAGE_LOW_PCT  0 to 100, default 10
    QUOTA_CLI      path to quota-cli                       (default: PATH, then ~/.cargo/bin)
    QUOTA_WATCH    optional path to a Python file that defines run_quota_cli(None) -> {stdout,
                   stderr, returncode}: a drop-in for quota-cli that works around its Windows
                   problem with Cursor. It runs in a separate Python process, so a hang, a crash or a
                   sys.exit in it cannot hurt this check; if it fails, quota-cli is used instead.
    HERMES         path to hermes                          (default: PATH, then %LOCALAPPDATA%/hermes/bin on
                                                            Windows or ~/.local/bin elsewhere)
"""
from __future__ import annotations

import json
import math
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
SETTINGS = ("USAGE_LOW_PCT", "QUOTA_CLI", "QUOTA_WATCH", "HERMES")
PATH_SETTINGS = ("QUOTA_CLI", "QUOTA_WATCH", "HERMES")
QUOTA_RUNNERS = ("claude", "codex", "cursor")
AGY_RUNNERS = ("agy-gemini", "agy-claude")
RUNNERS = QUOTA_RUNNERS + AGY_RUNNERS
WINDOW_NAMES = {"5h": "5-hour", "wk": "week", "weekly": "week", "plan": "plan period"}
WATCH_TIMEOUT = 40    # seconds for the QUOTA_WATCH helper
QUOTA_TIMEOUT = 40    # seconds for quota-cli
HERMES_TIMEOUT = 60   # seconds for hermes usage

# Runs in its own Python process: imports the helper by file name and prints its answer as one JSON line.
WATCH_HELPER = (
    "import importlib, json, sys\n"
    "sys.path.insert(0, sys.argv[1])\n"
    "raw = importlib.import_module(sys.argv[2]).run_quota_cli(None)\n"
    "print(json.dumps({'stdout': raw.get('stdout'), 'stderr': raw.get('stderr')}))\n"
)

# What must never reach the output: an email address, a home folder (C:\Users\<name>,
# /Users/<name>, /home/<name>), a long token.
HIDE = re.compile(
    r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"
    r"|[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s]+"
    r"|/(?:Users|home)/[^/\s]+"
    r"|\b(?=[\w-]*\d)(?=[\w-]*[A-Za-z])[\w-]{24,}\b"
)


def scrub(text: str) -> str:
    return HIDE.sub("<hidden>", str(text))


# ----------------------------------------------------------------------------- settings
def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):  # UTF-16, which Windows PowerShell 5.1 writes by default
        return raw.decode("utf-16")
    return raw.decode("utf-8-sig")  # also drops a UTF-8 byte-order mark


def load_settings() -> dict:
    cfg: dict = {}
    try:
        for line in read_text(SKILL / "local.env").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                cfg[key.strip()] = value.strip().strip('"').strip("'")
    except (OSError, UnicodeError):
        pass
    cfg.update({k: os.environ[k] for k in SETTINGS if os.environ.get(k)})  # the real environment wins
    for key in PATH_SETTINGS:
        if cfg.get(key):
            cfg[key] = os.path.expandvars(os.path.expanduser(cfg[key]))
    return cfg


def low_threshold(cfg: dict) -> float:
    try:
        value = float(cfg.get("USAGE_LOW_PCT", "10"))
    except (TypeError, ValueError):
        return 10.0
    return value if math.isfinite(value) and 0 <= value <= 100 else 10.0


# ----------------------------------------------------------------------------- numbers
def number(value):
    """A finite number, or None. A boolean, a string and NaN are not numbers here."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    return float(value)


def percent(value):
    v = number(value)
    return v if v is not None and 0 <= v <= 100 else None


def epoch(value):
    """Seconds since 1970, or None. A value in milliseconds is converted; only 2000 to 2100 is believed."""
    v = number(value)
    if v is None:
        return None
    if v > 1e11:
        v /= 1000
    return v if 946684800 <= v <= 4102444800 else None


def iso_epoch(value):
    try:
        return epoch(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp())
    except (ValueError, OverflowError, OSError):
        return None


def window(label, left, reset) -> dict:
    name = str(label or "?").strip()
    return {"name": WINDOW_NAMES.get(name.lower(), name), "left": percent(left), "reset": epoch(reset)}


def unknown(why: str, runners) -> dict:
    return {r: {"windows": [], "problem": why} for r in runners}


def first_line(text: str, limit: int = 140) -> str:
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()[:limit]
    return ""


def load_json(text, opener: str):
    """The first JSON value in text that starts at `opener` ("[" or "{"); text around it is ignored,
    including a stray bracket in a banner before it."""
    text = text or ""
    start = text.find(opener)
    while start >= 0:
        try:
            return json.JSONDecoder().raw_decode(text, start)[0]
        except ValueError:
            start = text.find(opener, start + 1)
    raise ValueError("no JSON")


def run(cmd, timeout, env=None):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                          timeout=timeout, env=env)


# ----------------------------------------------------------------------------- quota-cli
def parse_quota(stdout, stderr) -> dict:
    """quota-cli's JSON array -> {runner: {"windows": [...], "problem": ...}} for claude, codex, cursor."""
    errors = {}
    for line in (stderr or "").splitlines():
        m = re.match(r"^([a-z][a-z0-9_-]*):\s*(.+)$", line.strip())
        if m:
            errors[m.group(1)] = m.group(2)[:140]
    try:
        data = load_json(stdout, "[")
    except ValueError:
        data = None
    if not isinstance(data, list):
        return unknown(first_line(stderr) or "quota-cli gave no usable answer", QUOTA_RUNNERS)
    out: dict = {}
    for rec in data:
        if isinstance(rec, dict) and rec.get("provider") in QUOTA_RUNNERS:
            wins = [window(w.get("label"), w.get("remainingPercent"), w.get("resetAt"))
                    for w in (rec.get("windows") or []) if isinstance(w, dict)]
            out[rec["provider"]] = {"windows": wins, "problem": None if wins else str(rec.get("note") or "no windows reported")[:140]}
    for r in QUOTA_RUNNERS:
        out.setdefault(r, {"windows": [], "problem": errors.get(r) or "not reported"})
    return out


def via_watch_script(watch: Path) -> dict:
    cp = run([sys.executable, "-B", "-c", WATCH_HELPER, str(watch.resolve().parent), watch.stem], WATCH_TIMEOUT)
    raw = json.loads(cp.stdout.strip().splitlines()[-1])
    return parse_quota(raw.get("stdout"), raw.get("stderr"))


def via_quota_cli(cfg: dict) -> dict:
    default = Path.home() / ".cargo" / "bin" / ("quota-cli.exe" if os.name == "nt" else "quota-cli")
    exe = cfg.get("QUOTA_CLI") or shutil.which("quota-cli") or str(default)
    if not (Path(exe).is_file() or shutil.which(exe)):
        return unknown("quota-cli not found (cargo install quota-cli)", QUOTA_RUNNERS)
    env = dict(os.environ)
    if os.name == "nt" and not env.get("XDG_CONFIG_HOME") and env.get("APPDATA"):
        env["XDG_CONFIG_HOME"] = env["APPDATA"]  # where the Cursor CLI keeps its login on Windows
    try:
        cp = run([exe, "usage", "--json"], QUOTA_TIMEOUT, env)
    except subprocess.TimeoutExpired:
        return unknown("quota-cli timed out", QUOTA_RUNNERS)
    except OSError as exc:
        return unknown(f"quota-cli would not start: {exc}", QUOTA_RUNNERS)
    return parse_quota(cp.stdout, cp.stderr)


def collect_quota(cfg: dict) -> dict:
    watch = cfg.get("QUOTA_WATCH")
    if watch and Path(watch).is_file():
        try:
            result = via_watch_script(Path(watch))
            if any(info["windows"] for info in result.values()):
                return result
        except Exception:  # it hung, crashed or answered with nonsense: ask quota-cli itself
            pass
    return via_quota_cli(cfg)


# ----------------------------------------------------------------------------- Hermes, for agy
def collect_agy(cfg: dict) -> dict:
    if os.name == "nt":
        local = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        default = Path(local) / "hermes" / "bin" / "hermes.exe"
    else:
        default = Path.home() / ".local" / "bin" / "hermes"
    exe = cfg.get("HERMES") or shutil.which("hermes") or str(default)
    if not (Path(exe).is_file() or shutil.which(exe)):
        return unknown("Hermes not found", AGY_RUNNERS)
    try:
        cp = run([exe, "usage", "--provider", "antigravity-subscription-directsdk", "--json"], HERMES_TIMEOUT)
    except subprocess.TimeoutExpired:
        return unknown("hermes usage timed out", AGY_RUNNERS)
    except OSError as exc:
        return unknown(f"Hermes would not start: {exc}", AGY_RUNNERS)
    if cp.returncode != 0:
        return unknown("hermes usage failed: " + (first_line(cp.stderr) or f"exit {cp.returncode}"), AGY_RUNNERS)
    try:
        doc = load_json(cp.stdout, "{")
    except ValueError:
        return unknown("hermes usage gave no usable answer", AGY_RUNNERS)
    if not isinstance(doc, dict):
        return unknown("hermes usage gave no usable answer", AGY_RUNNERS)
    out = {r: {"windows": [], "problem": str(doc.get("unavailable_reason") or "Hermes reported no windows for it")[:140]}
           for r in AGY_RUNNERS}
    windows = doc.get("windows")
    for w in windows if isinstance(windows, list) else []:
        if not isinstance(w, dict):
            continue
        m = re.match(r"^\s*(Gemini|Claude/GPT)\s*\((.+)\)\s*$", str(w.get("label")))
        if not m:
            continue
        used = percent(w.get("used_percent"))
        runner = "agy-gemini" if m.group(1) == "Gemini" else "agy-claude"
        out[runner]["windows"].append(window(m.group(2), None if used is None else 100 - used, iso_epoch(w.get("resets_at"))))
    return out


# ----------------------------------------------------------------------------- the report
def fmt_pct(x: float) -> str:
    return f"{x:.0f}%" if abs(x - round(x)) < 0.05 else f"{x:.1f}%"


def fmt_reset(ts) -> str:
    try:
        return datetime.fromtimestamp(ts).strftime("%a %b %d %H:%M")
    except (OverflowError, OSError, ValueError):
        return ""


def describe(info: dict, low_pct: float):
    """-> (state, detail). state is ok, LOW or unknown. LOW means 'low_pct or less left', unrounded."""
    wins = info.get("windows") or []
    if not wins or all(w["left"] is None for w in wins):
        return "unknown", scrub(info.get("problem") or "no data")
    low, parts = False, []
    for w in sorted(wins, key=lambda w: {"5-hour": 0, "week": 1}.get(w["name"], 2)):  # short window first
        if w["left"] is None:
            parts.append(f"{w['name']} ? left")
            continue
        is_low = w["left"] <= low_pct
        low = low or is_low
        when = fmt_reset(w["reset"]) if w["reset"] else ""
        parts.append(f"{w['name']} {fmt_pct(w['left'])} left{' LOW' if is_low else ''}{f' (resets {when})' if when else ''}")
    return ("LOW" if low else "ok"), "; ".join(parts)


def safe(fn, cfg: dict, runners) -> dict:
    try:
        return fn(cfg)
    except Exception as exc:  # one source failing must not take the others down with it
        return unknown(f"{fn.__name__} failed: {type(exc).__name__}", runners)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    try:
        cfg = load_settings()
        low_pct = low_threshold(cfg)
        with ThreadPoolExecutor(max_workers=2) as pool:
            quota = pool.submit(safe, collect_quota, cfg, QUOTA_RUNNERS)
            agy = pool.submit(safe, collect_agy, cfg, AGY_RUNNERS)
            results = {**quota.result(), **agy.result()}
    except Exception as exc:  # advisory only: whatever went wrong, say so and carry on
        low_pct = 10.0
        results = unknown(f"usage check failed: {type(exc).__name__}", RUNNERS)
    print(f"usage checked {datetime.now().strftime('%a %b %d %H:%M')}; LOW = {low_pct:g}% or less left in any window")
    low, unsure = [], []
    for runner in RUNNERS:
        try:
            state, detail = describe(results.get(runner) or {}, low_pct)
        except Exception:
            state, detail = "unknown", "its numbers could not be read"
        print(f"{runner:<11} {state:<8} {detail}")
        (low if state == "LOW" else unsure if state == "unknown" else []).append(runner)
    print("LOW: " + (", ".join(low) or "none"))
    print("UNKNOWN: " + (", ".join(unsure) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
