#!/usr/bin/env python3
"""End-to-end ACP approval smoke test for Goose and the local Kiro shim.

The test creates a temporary file containing a random nonce that is never included
in the model prompt. The model is asked to read the file with the shell/developer
tool. In approve mode the ACP agent must send session/request_permission; this
client answers with the advertised allow_once option. PASS requires both the
permission request and the previously unknown nonce to appear on the ACP wire.
"""

from __future__ import annotations

import json
import os
import queue
import secrets
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

TIMEOUT_SECS = int(os.environ.get("KIRO_ACP_SMOKE_TIMEOUT", "240"))


class SmokeError(RuntimeError):
    pass


@dataclass
class Target:
    name: str
    argv: list[str]
    protocol_version: Any
    mode_id: str


class AcpProcess:
    def __init__(self, target: Target, env: dict[str, str]):
        self.target = target
        self.proc = subprocess.Popen(
            target.argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        if not self.proc.stdin or not self.proc.stdout or not self.proc.stderr:
            raise SmokeError("failed to open ACP stdio pipes")
        self.stdin = self.proc.stdin
        self.stdout = self.proc.stdout
        self.stderr = self.proc.stderr
        self.next_id = 1
        self.transcript: list[dict[str, Any]] = []
        self.stderr_lines: list[str] = []
        self.permission_observed = False
        self.tool_call_observed = False
        self._stdout_queue: queue.Queue[str | None] = queue.Queue()
        self._stdout_thread = threading.Thread(target=self._drain_stdout, daemon=True)
        self._stderr_thread = threading.Thread(target=self._drain_stderr, daemon=True)
        self._stdout_thread.start()
        self._stderr_thread.start()

    def _drain_stdout(self) -> None:
        try:
            for line in self.stdout:
                self._stdout_queue.put(line)
        finally:
            self._stdout_queue.put(None)

    def _drain_stderr(self) -> None:
        try:
            for line in self.stderr:
                self.stderr_lines.append(line.rstrip("\n"))
        except Exception:
            pass

    def close(self) -> None:
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=3)

    def send_obj(self, obj: dict[str, Any]) -> None:
        self.stdin.write(json.dumps(obj, separators=(",", ":")) + "\n")
        self.stdin.flush()

    def _read_obj(self, deadline: float) -> dict[str, Any]:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SmokeError("timed out waiting for ACP output")
            try:
                line = self._stdout_queue.get(timeout=min(remaining, 1.0))
            except queue.Empty:
                if self.proc.poll() is not None:
                    raise SmokeError(f"ACP process exited with status {self.proc.returncode}")
                continue
            if line is None:
                raise SmokeError(f"ACP stdout closed (status={self.proc.poll()})")
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SmokeError(f"non-JSON ACP stdout: {line[:300]}") from exc
            if isinstance(obj, dict):
                self.transcript.append(obj)
                return obj

    @staticmethod
    def _permission_option(params: dict[str, Any]) -> str | None:
        options = params.get("options")
        if not isinstance(options, list):
            return None
        for item in options:
            if not isinstance(item, dict) or item.get("kind") != "allow_once":
                continue
            option_id = item.get("optionId", item.get("id"))
            if isinstance(option_id, str) and option_id:
                return option_id
        return None

    def _handle_server_request(self, msg: dict[str, Any]) -> bool:
        method = msg.get("method")
        if method != "session/request_permission" or "id" not in msg:
            return False

        params = msg.get("params") or {}
        if not isinstance(params, dict):
            params = {}
        option_id = self._permission_option(params)
        self.permission_observed = True
        print("  ✓ ACP permission request observed")

        tool_call = params.get("toolCall")
        if isinstance(tool_call, dict):
            title = tool_call.get("title") or tool_call.get("toolCallId") or "tool"
            print(f"    tool: {title}")

        if option_id is None:
            self.send_obj(
                {
                    "jsonrpc": "2.0",
                    "id": msg["id"],
                    "result": {"outcome": {"outcome": "cancelled"}},
                }
            )
            raise SmokeError("permission request had no allow_once option")

        print(f"    answering with allow_once ({option_id})")
        self.send_obj(
            {
                "jsonrpc": "2.0",
                "id": msg["id"],
                "result": {
                    "outcome": {"outcome": "selected", "optionId": option_id}
                },
            }
        )
        return True

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        request_id = self.next_id
        self.next_id += 1
        self.send_obj(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params,
            }
        )
        deadline = time.monotonic() + TIMEOUT_SECS
        while True:
            msg = self._read_obj(deadline)

            # ACP is bidirectional JSON-RPC: the agent may ask the client to
            # approve a tool while our session/prompt request is still pending.
            if "method" in msg and "id" in msg:
                if self._handle_server_request(msg):
                    continue
                raise SmokeError(f"unexpected ACP server request: {msg.get('method')}")

            # Notifications carry tool-call lifecycle and streamed model output.
            if "method" in msg and "id" not in msg:
                params_obj = msg.get("params") or {}
                update = params_obj.get("update") if isinstance(params_obj, dict) else None
                if isinstance(update, dict):
                    update_type = update.get("sessionUpdate")
                    if update_type in {"tool_call", "tool_call_update"}:
                        self.tool_call_observed = True
                        title = update.get("title") or update.get("toolCallId") or update_type
                        status = update.get("status")
                        suffix = f" ({status})" if status else ""
                        print(f"  · {update_type}: {title}{suffix}")
                continue

            if msg.get("id") == request_id:
                if "error" in msg:
                    raise SmokeError(f"ACP RPC {method} failed: {msg['error']}")
                result = msg.get("result")
                return result if isinstance(result, dict) else {}

    def wire_contains(self, needle: str) -> bool:
        return any(needle in json.dumps(item, ensure_ascii=False) for item in self.transcript)


def build_env() -> dict[str, str]:
    env = os.environ.copy()
    env["GOOSE_MODE"] = "approve"
    env["GOOSE_TOOLSHIM"] = "1"
    model = env.get("GOOSE_TOOLSHIM_OLLAMA_MODEL") or env.get("GOOSE_MODEL") or "qwen3:8b"
    env["GOOSE_TOOLSHIM_OLLAMA_MODEL"] = model
    return env


def run_target(target: Target, probe: Path, nonce: str) -> bool:
    print(f"\n=== {target.name} ===")
    print("  argv:", " ".join(target.argv))
    client = AcpProcess(target, build_env())
    try:
        init = client.request(
            "initialize",
            {
                "protocolVersion": target.protocol_version,
                "clientCapabilities": {},
                "clientInfo": {"name": "kiro-local-acp-smoke", "version": "1"},
            },
        )
        print(f"  ✓ initialize: protocol={init.get('protocolVersion', '?')}")

        new = client.request(
            "session/new",
            {"mcpServers": [], "cwd": os.getcwd()},
        )
        session_id = new.get("sessionId")
        if not isinstance(session_id, str) or not session_id:
            raise SmokeError(f"session/new returned no sessionId: {new}")
        print(f"  ✓ session/new: {session_id}")

        client.request(
            "session/set_mode",
            {"sessionId": session_id, "modeId": target.mode_id},
        )
        print(f"  ✓ mode selected: {target.mode_id}")

        prompt = (
            f"Use the available developer/shell tool to read the file {probe}. "
            "Return the exact file contents. Do not guess, infer, simulate, or fabricate it."
        )
        final = client.request(
            "session/prompt",
            {
                "sessionId": session_id,
                "prompt": [{"type": "text", "text": prompt}],
            },
        )
        print(f"  ✓ prompt completed: stopReason={final.get('stopReason', '?')}")

        nonce_seen = client.wire_contains(nonce)
        print(f"  permission request: {'YES' if client.permission_observed else 'NO'}")
        print(f"  tool call/update:   {'YES' if client.tool_call_observed else 'NO'}")
        print(f"  nonce on ACP wire:  {'YES' if nonce_seen else 'NO'}")

        if client.permission_observed and client.tool_call_observed and nonce_seen:
            print(f"ACP APPROVAL TEST PASSED: {target.name}")
            return True

        print(f"ACP APPROVAL TEST FAILED: {target.name}")
        return False
    except Exception as exc:
        print(f"ACP APPROVAL TEST ERROR: {target.name}: {exc}")
        if client.stderr_lines:
            print("  --- ACP stderr tail ---")
            for line in client.stderr_lines[-30:]:
                print("  " + line)
        return False
    finally:
        client.close()


def main() -> int:
    goose_bin = os.environ.get(
        "GOOSE_BIN",
        str(Path.home() / ".local/share/kiro-local/runtime-home/.local/bin/goose"),
    )
    adapter_bin = os.environ.get(
        "KIROCREW_KIRO_BIN",
        str(Path.home() / ".local/share/kiro-local/bin/kiro-cli-local"),
    )

    if not Path(goose_bin).is_file():
        print(f"Goose binary not found: {goose_bin}", file=sys.stderr)
        return 2

    nonce = "KIRO_ACP_APPROVE_OK_" + secrets.token_hex(16)
    fd, probe_name = tempfile.mkstemp(prefix="kiro-acp-approve-test.")
    probe = Path(probe_name)
    try:
        os.write(fd, (nonce + "\n").encode())
        os.close(fd)
        os.chmod(probe, 0o600)

        targets = [
            Target("direct Goose ACP", [goose_bin, "acp"], 1, "approve"),
        ]
        if Path(adapter_bin).is_file():
            targets.append(
                Target(
                    "local Kiro→Goose ACP adapter",
                    [adapter_bin, "acp", "--agent", "kirocrew"],
                    "2025-08-22",
                    "kirocrew",
                )
            )
        else:
            print(f"Adapter not found, skipping adapter leg: {adapter_bin}")

        results = [run_target(target, probe, nonce) for target in targets]
        print("\n=== Summary ===")
        for target, ok in zip(targets, results):
            print(f"  {'PASS' if ok else 'FAIL'}  {target.name}")
        print(f"  expected nonce: {nonce}")

        return 0 if all(results) else 1
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            probe.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
