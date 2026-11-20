#!/usr/bin/env python3
"""Drives mynahpad-mcp over stdio and checks each tool. Called by test.sh."""
import json
import subprocess
import sys
from pathlib import Path

binary, home = sys.argv[1], Path(sys.argv[2])
store = home / ".config" / "mynahpad" / "notes.json"
proc = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
next_id = 0
failures = 0


def rpc(method, params=None):
    global next_id
    next_id += 1
    msg = {"jsonrpc": "2.0", "id": next_id, "method": method}
    if params is not None:
        msg["params"] = params
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    return json.loads(proc.stdout.readline())


def call(tool, **args):
    result = rpc("tools/call", {"name": tool, "arguments": args})["result"]
    return result.get("structuredContent"), result.get("isError", False)


def check(name, ok):
    global failures
    if not ok:
        failures += 1
    print("PASS" if ok else "FAIL", name)


init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "test", "version": "0"}})["result"]
check("initialize", init["serverInfo"]["name"] == "mynahpad")
names = [t["name"] for t in rpc("tools/list")["result"]["tools"]]
check("tools/list", names == ["list_folders", "create_folder", "add_notes", "list_notes",
                              "update_note", "delete_notes", "reset_folder"])

folders, _ = call("list_folders")
check("list_folders seeds general", [f["id"] for f in folders["folders"]] == ["general"])
check("store is under the throwaway home", store.exists())

parent, _ = call("create_folder", name="Runbook")
pid = parent["folder"]["id"]
child, _ = call("create_folder", name="UAT", parent_id=pid)
check("create_folder nests", child["folder"]["parent_id"] == pid)
_, err = call("create_folder", name="x", parent_id="missing")
check("create_folder rejects unknown parent", err)

call("add_notes", folder_id=pid, texts=["one", "two", "three"])
call("add_notes", folder_id=pid, texts=["zero"])
call("add_notes", folder_id=pid, texts=["last"], position="bottom")
call("add_notes", folder_id="general", texts=["elsewhere"])
notes, _ = call("list_notes", folder_id=pid)
check("add_notes keeps order (top, then bottom)",
      [n["text"] for n in notes["notes"]] == ["zero", "one", "two", "three", "last"])
_, err = call("add_notes", folder_id="missing", texts=["x"])
check("add_notes rejects unknown folder", err)
_, err = call("add_notes", folder_id=pid, texts=["ok", "  "])
check("add_notes rejects empty text", err)

first = notes["notes"][0]["id"]
updated, _ = call("update_note", id=first, text="zero v2")
check("update_note", updated["note"]["text"] == "zero v2")
_, err = call("update_note", id=first, text=" ")
check("update_note rejects empty text", err)

# Mark two notes used straight in the file, as the app would.
doc = json.loads(store.read_text())
for n in doc["notes"]:
    if n["folder_id"] == pid and n["text"] in ("one", "two"):
        n["used"] = True
store.write_text(json.dumps(doc))
reset, _ = call("reset_folder", folder_id=pid)
check("reset_folder", reset["reset"] == 2)

_, err = call("delete_notes", ids=[first, "missing"])
still, _ = call("list_notes", folder_id=pid)
check("delete_notes with an unknown id deletes nothing", err and len(still["notes"]) == 5)
call("delete_notes", ids=[first])
doc = json.loads(store.read_text())
check("delete_notes moves the note to trash",
      all(n["id"] != first for n in doc["notes"]) and doc["trash"][0]["note"]["id"] == first)

everything, _ = call("list_notes")
check("list_notes without folder returns all", len(everything["notes"]) == 5)

store.write_text("{ not json")
_, err = call("list_folders")
check("unreadable notes.json is an error, not overwritten", err and store.read_text() == "{ not json")

check("unknown method", rpc("bogus")["error"]["code"] == -32601)

proc.stdin.close()
proc.wait(timeout=5)
print("All MCP checks passed" if failures == 0 else f"{failures} MCP check(s) failed")
sys.exit(0 if failures == 0 else 1)
