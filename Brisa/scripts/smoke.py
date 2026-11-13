#!/usr/bin/env python3
"""Real executable tests; no app state writes and no destructive requests."""
import json
import pathlib
import subprocess
import sys
import tempfile
import secrets

bin_dir = pathlib.Path(sys.argv[1]).resolve()
cli = bin_dir / "brisa"
for args, code in [(["version", "--json"], 0), (["help", "--json"], 0), (["clean", "--yes", "--json"], 2), (["findings", "--limit", "0", "--json"], 2), (["unknown", "--json"], 2)]:
    result = subprocess.run([str(cli), *args], capture_output=True, text=True, timeout=10)
    assert result.returncode == code, (args, result.stderr, result.stdout)
    envelope = json.loads(result.stdout)
    assert envelope["ok"] == (code == 0), envelope

messages = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "delete", "arguments": {}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "file_info", "arguments": {"path": "/etc/passwd"}}},
]
result = subprocess.run([str(bin_dir / "brisa-mcp")], input="".join(json.dumps(m) + "\n" for m in messages), capture_output=True, text=True, timeout=10)
assert result.returncode == 0, result.stderr
responses = [json.loads(line) for line in result.stdout.splitlines()]
assert len(responses) == 4, responses
tools = responses[1]["result"]["tools"]
assert len(tools) == 9
assert all(t["name"] not in {"clean", "delete", "quit", "settings", "select"} for t in tools)
assert responses[2]["error"]["code"] == -32602
assert responses[3]["error"]["code"] == -32602
oversized = subprocess.run([str(bin_dir / "brisa-mcp")], input="x" * 65537 + "\n", capture_output=True, text=True, timeout=10)
assert oversized.returncode == 2

# Build cleanup may remove marked snapshots, never an arbitrary path or symlink target.
cleanup = pathlib.Path(__file__).with_name("cleanup-build.py").resolve()
refused = subprocess.run([sys.executable, str(cleanup), str(pathlib.Path.cwd())], capture_output=True, text=True, timeout=10)
assert refused.returncode != 0
with tempfile.TemporaryDirectory(prefix="BrisaCleanupTarget-") as target:
    sentinel = pathlib.Path(target) / "keep.txt"
    sentinel.write_text("keep")
    snapshot = pathlib.Path(tempfile.gettempdir()) / ("BrisaBuild." + secrets.token_hex(3))
    snapshot.mkdir(mode=0o700)
    (snapshot / ".brisa-build").write_text("Brisa disposable build snapshot v1\n")
    (snapshot / "link").symlink_to(target, target_is_directory=True)
    removed = subprocess.run([sys.executable, str(cleanup), str(snapshot)], capture_output=True, text=True, timeout=10)
    assert removed.returncode == 0, removed.stderr
    assert not snapshot.exists()
    assert sentinel.read_text() == "keep"
print("Executable smoke checks passed: CLI JSON, exit codes, MCP handshake, tool boundary, frame limit, guarded snapshot cleanup.")
