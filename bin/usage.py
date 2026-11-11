#!/usr/bin/env python3
"""How much allowance each build runner has left: one line per runner. Read-only; never blocks a build.

    python -I usage.py

Runners and where each one is read from. Every source is optional: a source that is missing or
fails makes its runners "unknown", never "low".
    claude, codex, cursor   quota-cli (`cargo install quota-cli`), which reads each CLI's stored login
                            read-only and never refreshes it
    agy-gemini, agy-claude  Hermes: `hermes usage --provider antigravity-subscription-directsdk --json`
                            (agy-gemini is what Gemini Carbon and Flash use; agy-claude is the Claude
                            and GPT models agy offers)

A runner is LOW when any of its windows has USAGE_LOW_PCT percent or less left.

Settings come from the environment, or from local.env next to SKILL.md (git ignores that file):
    USAGE_LOW_PCT  default 10
    QUOTA_CLI      path to quota-cli                       (default: PATH, then ~/.cargo/bin)
    QUOTA_WATCH    optional path to a Python file that defines run_quota_cli(None) -> {stdout,
                   stderr, returncode}: a drop-in for quota-cli that works around its Windows
                   problem with Cursor. Used before QUOTA_CLI when it exists.
    HERMES         path to hermes                          (default: PATH, then %LOCALAPPDATA%/hermes/bin)
"""
from __future__ import annotations

import importlib
import json
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
QUOTA_RUNNERS = ("claude", "codex", "cursor")
AGY_RUNNERS = ("agy-gemini", "agy-claude")
RUNNERS = QUOTA_RUNNERS + AGY_RUNNERS
WINDOW_NAMES = {"5h": "5-hour", "wk": "week", "weekly": "week", "plan": "plan period"}


def load_settings() -> dict:
    cfg: dict = {}
    try:
        for line in (SKILL / "local.env").read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                cfg[key.strip()] = value.strip().strip('"').strip("'")
    except OSError:
        pass
    cfg.update({k: os.environ[k] for k in SETTINGS if os.environ.get(k)})  # the real environment wins
    return cfg


def number(value):
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def window(label, left, reset) -> dict:
    name = str(label or "?").strip()
    return {"name": WINDOW_NAMES.get(name.lower(), name), "left": number(left), "reset": number(reset)}


def unknown(why: str, runners) -> dict:
    return {r: {"windows": [], "problem": why} for r in runners}


def first_line(text: str, limit: int = 140) -> str:
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()[:limit]
    return ""


# ----------------------------------------------------------------------------- quota-cli
def parse_quota(stdout, stderr) -> dict:
    """quota-cli's JSON array -> {runner: {"windows": [...], "problem": ...}} for claude, codex, cursor."""
    errors = {}
    for line in (stderr or "").splitlines():
        m = re.match(r"^([a-z][a-z0-9_-]*):\s*(.+)$", line.strip())
        if m:
            errors[m.group(1)] = m.group(2)[:140]
    try:
        data = json.loads(stdout or "null")
    except ValueError:
        data = None
    if not isinstance(data, list):
        return unknown(first_line(stderr) or "quota-cli gave no usable answer", QUOTA_RUNNERS)
    out: dict = {}
    for rec in data:
        if isinstance(rec, dict) and rec.get("provider") in QUOTA_RUNNERS:
            wins = [window(w.get("label"), w.get("remainingPercent"), w.get("resetAt"))
                    for w in (rec.get("windows") or []) if isinstance(w, dict)]
            out[rec["provider"]] = {"windows": wins, "problem": None if wins else str(rec.get("note") or "no windows reported")}
    for r in QUOTA_RUNNERS:
        out.setdefault(r, {"windows": [], "problem": errors.get(r) or "not reported"})
    return out


def collect_quota(cfg: dict) -> dict:
    watch = cfg.get("QUOTA_WATCH")
    if watch and Path(watch).is_file():
        try:
            sys.path.insert(0, str(Path(watch).resolve().parent))
            raw = importlib.import_module(Path(watch).stem).run_quota_cli(None)
            return parse_quota(raw.get("stdout"), raw.get("stderr"))
        except Exception:  # fall back to quota-cli itself
            pass
    exe = cfg.get("QUOTA_CLI") or shutil.which("quota-cli") or str(Path.home() / ".cargo" / "bin" / "quota-cli.exe")
    if not (Path(exe).is_file() or shutil.which(exe)):
        return unknown("quota-cli not found (cargo install quota-cli)", QUOTA_RUNNERS)
    env = dict(os.environ)
    if os.name == "nt" and not env.get("XDG_CONFIG_HOME") and env.get("APPDATA"):
        env["XDG_CONFIG_HOME"] = env["APPDATA"]  # where the Cursor CLI keeps its login on Windows
    try:
        cp = subprocess.run([exe, "usage", "--json"], capture_output=True, text=True, env=env,
                            encoding="utf-8", errors="replace", timeout=130)
    except subprocess.TimeoutExpired:
        return unknown("quota-cli timed out", QUOTA_RUNNERS)
    except OSError as exc:
        return unknown(f"quota-cli would not start: {exc}"[:140], QUOTA_RUNNERS)
    return parse_quota(cp.stdout, cp.stderr)


# ----------------------------------------------------------------------------- Hermes, for agy
def collect_agy(cfg: dict) -> dict:
    local = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    exe = cfg.get("HERMES") or shutil.which("hermes") or str(Path(local) / "hermes" / "bin" / "hermes.exe")
    if not (Path(exe).is_file() or shutil.which(exe)):
        return unknown("Hermes not found", AGY_RUNNERS)
    try:
        cp = subprocess.run([exe, "usage", "--provider", "antigravity-subscription-directsdk", "--json"],
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
    except subprocess.TimeoutExpired:
        return unknown("hermes usage timed out", AGY_RUNNERS)
    except OSError as exc:
        return unknown(f"Hermes would not start: {exc}"[:140], AGY_RUNNERS)
    if cp.returncode != 0:
        return unknown("hermes usage failed: " + (first_line(cp.stderr) or f"exit {cp.returncode}"), AGY_RUNNERS)
    try:
        doc = json.loads(cp.stdout[cp.stdout.index("{"):])
    except ValueError:
        return unknown("hermes usage gave no usable answer", AGY_RUNNERS)
    out = {r: {"windows": [], "problem": doc.get("unavailable_reason") or "Hermes reported no windows for it"} for r in AGY_RUNNERS}
    for w in doc.get("windows") or []:
        m = re.match(r"^\s*(Gemini|Claude/GPT)\s*\((.+)\)\s*$", str((w or {}).get("label")))
        if not m:
            continue
        used = number(w.get("used_percent"))
        try:
            reset = datetime.fromisoformat(str(w.get("resets_at"))).timestamp()
        except ValueError:
            reset = None
        runner = "agy-gemini" if m.group(1) == "Gemini" else "agy-claude"
        out[runner]["windows"].append(window(m.group(2), None if used is None else 100 - used, reset))
    return out


# ----------------------------------------------------------------------------- the report
def describe(info: dict, low_pct: float):
    """-> (state, detail). state is ok, LOW or unknown."""
    wins = info.get("windows") or []
    if not wins or all(w["left"] is None for w in wins):
        return "unknown", info.get("problem") or "no data"
    low, parts = False, []
    for w in sorted(wins, key=lambda w: {"5-hour": 0, "week": 1}.get(w["name"], 2)):  # short window first
        if w["left"] is None:
            parts.append(f"{w['name']} ? left")
            continue
        left = round(w["left"])
        flag = " LOW" if left <= low_pct else ""
        low = low or bool(flag)
        when = f" (resets {datetime.fromtimestamp(w['reset']).strftime('%a %b %d %H:%M')})" if w["reset"] else ""
        parts.append(f"{w['name']} {left}% left{flag}{when}")
    return ("LOW" if low else "ok"), "; ".join(parts)


def main() -> int:
    cfg = load_settings()
    try:
        low_pct = float(cfg.get("USAGE_LOW_PCT", "10"))
    except ValueError:
        low_pct = 10.0
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            quota, agy = pool.submit(collect_quota, cfg), pool.submit(collect_agy, cfg)
            results = {**quota.result(), **agy.result()}
    except Exception as exc:  # advisory only: whatever went wrong, say so and carry on
        results = unknown(f"usage check failed: {type(exc).__name__}", RUNNERS)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    print(f"usage checked {datetime.now().strftime('%a %b %d %H:%M')}; LOW = {low_pct:g}% or less left in any window")
    low, unsure = [], []
    for runner in RUNNERS:
        state, detail = describe(results.get(runner) or {}, low_pct)
        print(f"{runner:<11} {state:<8} {detail}")
        (low if state == "LOW" else unsure if state == "unknown" else []).append(runner)
    print("LOW: " + (", ".join(low) or "none"))
    print("UNKNOWN: " + (", ".join(unsure) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
