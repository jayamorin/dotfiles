"""Merge the team's Claude Code settings into a user's ~/.claude/settings.json, and take them out again.

Claude Code has one user-level settings file and writes to it itself (/model, /config), so it can't be a
symlink into this repo. Instead the team file is merged in:

- objects merge key by key; a list gets the team entries it doesn't have yet (order kept);
- a value the user already set is never changed (a different value is reported, not overwritten);
- everything added is recorded in a state file, so `unmerge` removes exactly that and nothing else.

Usage (from install.sh):
  settings_merge.py merge   <team.json> <user settings.json> <state.json> [--dry-run]
  settings_merge.py unmerge <user settings.json> <state.json> [--dry-run]

Standard library only; run with `python3 -I`.
"""

from __future__ import annotations  # macOS's /usr/bin/python3 is 3.9

import json
import os
import sys
import tempfile
from typing import Any, List

Path = List[str]


def merge(user: dict[str, Any], team: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]], list[str]]:
    """Return (merged, added, conflicts). `added` entries: {"path": [...], "value": v, "item": bool}."""
    added: list[dict[str, Any]] = []
    conflicts: list[str] = []

    def walk(dst: dict[str, Any], src: dict[str, Any], path: Path) -> None:
        for key, value in src.items():
            here = [*path, key]
            if key not in dst:
                dst[key] = value
                added.append({"path": here, "value": value, "item": False})
            elif isinstance(dst[key], dict) and isinstance(value, dict):
                walk(dst[key], value, here)
            elif isinstance(dst[key], list) and isinstance(value, list):
                for item in value:
                    if item not in dst[key]:
                        dst[key].append(item)
                        added.append({"path": here, "value": item, "item": True})
            elif dst[key] != value:
                conflicts.append(f"{'.'.join(here)}: kept your {json.dumps(dst[key])} (team: {json.dumps(value)})")

    merged = json.loads(json.dumps(user))
    walk(merged, team, [])
    return merged, added, conflicts


def unmerge(user: dict[str, Any], added: list[dict[str, Any]]) -> dict[str, Any]:
    """Remove what `merge` recorded as added; drop objects and lists it leaves empty."""
    result = json.loads(json.dumps(user))
    for entry in reversed(added):
        *parents, key = entry["path"]
        node: Any = result
        for part in parents:
            node = node.get(part) if isinstance(node, dict) else None
            if node is None:
                break
        if not isinstance(node, dict) or key not in node:
            continue
        if entry["item"]:
            if isinstance(node[key], list) and entry["value"] in node[key]:
                node[key].remove(entry["value"])
        elif node[key] == entry["value"]:
            del node[key]
    return prune(result)


def prune(value: Any) -> Any:
    if isinstance(value, dict):
        out = {}
        for key, child in value.items():
            child = prune(child)
            if child == {} or child == []:
                continue
            out[key] = child
        return out
    return value


def load(path: str) -> dict[str, Any] | None:
    """The JSON object in `path`, {} if the file doesn't exist, None if it isn't a valid JSON object."""
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def write(path: str, data: Any) -> None:
    # Write next to the target, then rename, so Claude Code (which watches the file) never reads half a file.
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".settings-", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def describe(entry: dict[str, Any]) -> str:
    where = ".".join(entry["path"])
    return f"{where} += {json.dumps(entry['value'])}" if entry["item"] else f"{where} = {json.dumps(entry['value'])}"


def cmd_merge(team_path: str, user_path: str, state_path: str, dry_run: bool) -> int:
    team = load(team_path)
    if team is None:
        print(f"  error: {team_path} is not a JSON object", file=sys.stderr)
        return 1
    user = load(user_path)
    if user is None:
        print(f"  warning: {user_path} is not valid JSON; left untouched (fix it, then re-run)")
        return 0
    state = load(state_path) or {}
    created = state.get("created", not os.path.exists(user_path))
    merged, added, conflicts = merge(user, team)
    for line in conflicts:
        print(f"  note: {line}")
    if not added:
        print(f"  {user_path}: team settings already present")
        return 0
    for entry in added:
        print(f"  {'would add' if dry_run else 'added'} {describe(entry)}")
    if dry_run:
        return 0
    write(user_path, merged)
    write(state_path, {"created": created, "added": state.get("added", []) + added})
    return 0


def cmd_unmerge(user_path: str, state_path: str, dry_run: bool) -> int:
    state = load(state_path)
    if not state or not state.get("added"):
        return 0
    user = load(user_path)
    if user is None:
        print(f"  warning: {user_path} is not valid JSON; team settings not removed")
        return 0
    result = unmerge(user, state["added"])
    remove_file = state.get("created") and set(result) <= {"$schema"}
    if dry_run:
        print(f"  would remove the team settings from {user_path}" + (" (and the file)" if remove_file else ""))
        return 0
    if remove_file:
        if os.path.exists(user_path):
            os.remove(user_path)
        print(f"  removed {user_path} (it only held the team settings)")
    else:
        write(user_path, result)
        print(f"  removed the team settings from {user_path}")
    os.remove(state_path)
    return 0


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if len(args) == 4 and args[0] == "merge":
        return cmd_merge(args[1], args[2], args[3], dry_run)
    if len(args) == 3 and args[0] == "unmerge":
        return cmd_unmerge(args[1], args[2], dry_run)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
