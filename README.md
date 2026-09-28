# Kiro Local Sysadmin Stack

Experimental fully-local sysadmin-agent stack built from:

- Kiro Crew — dashboard, sessions, memory and orchestration
- Goose ACP — local agent/tool execution
- Ollama — local LLM inference
- a local ACP compatibility adapter between Kiro Crew and Goose

The Linux installer includes automatic Ollama model selection, NVIDIA/AMD/Intel GPU detection, Docker GPU passthrough, Kiro Crew managed-service/AppArmor setup, reset/reinstall helpers and diagnostics. Windows support remains experimental.

## Quick install from GitHub

Run as your normal login user. **Do not run the whole installer with `sudo`.** It requests sudo internally only for the few system-wide steps that need it.

```bash
git clone https://github.com/Nicqx/kiro-local-sysadmin-stack.git
cd kiro-local-sysadmin-stack
./install.sh
```

No manual bootstrap or unzip step is required.

The root installer also enables Goose ToolShim for the local Ollama model. This is important for smaller local models that sometimes describe a tool action in prose instead of emitting a valid structured tool call.

By default the main assistant model remains `qwen3:8b`, while ToolShim uses a separate lightweight `qwen2.5:3b` interpreter. Keeping the interpreter separate avoids asking the same reasoning model to parse its own malformed pseudo-tool/XML output. `./install.sh`, `./update.sh`, and `./toolshim-fix.sh` automatically pull/manage the interpreter model. Override it with `TOOLSHIM_MODEL=<ollama-model>` in `~/.config/kiro-local/stack.env` if needed.

## Prove real tool execution

Do not trust a model merely because it says that it executed a command. Run the grounded smoke test:

```bash
bash ./tool-smoke-test.sh
```

The test creates a random nonce in a private temporary file without showing the nonce to the model. Goose is asked to read the file through the developer/shell tool. The test passes only if that unknown value comes back, proving an actual tool read occurred.

To test the interactive ACP approval path separately, run:

```bash
bash ./acp-approval-smoke-test.sh
```

This runs the same unknown-nonce test twice: first against `goose acp` directly in `approve` mode, then through the local Kiro→Goose compatibility adapter. It answers a real ACP `session/request_permission` with the advertised `allow_once` option. A PASS therefore proves not just tool execution, but that the permission request and response travelled correctly over the ACP connection before the tool ran.

## Completely clean reinstall

```bash
./install.sh --reset
```

This removes stack-owned runtime/configuration/history/memory and downloaded Ollama models before installing again. Docker and GPU drivers are left intact.

## Fresh runtime reinstall while preserving persistent stack data

```bash
./install.sh --fresh
```

## Common commands

```bash
./status.sh
./doctor.sh --deep
./chat.sh
./token.sh 8h
./stop.sh
./start.sh
bash ./tool-smoke-test.sh
bash ./acp-approval-smoke-test.sh
./update.sh
./uninstall.sh
```

Local dashboard:

```text
http://127.0.0.1:5476
```

If the dashboard says the session expired, generate a fresh URL:

```bash
./token.sh 8h
```

and open the complete URL it prints.

## Resource-saving stop/start

To completely release the stack's CPU/GPU/RAM resources and keep it stopped across reboots:

```bash
./stop.sh
```

This disables and stops the Kiro Crew systemd service, stops the Ollama container, and changes the Ollama container restart policy to `no`.

To start the stack again and restore normal boot-time startup:

```bash
./start.sh
```

This restores the Ollama restart policy to `unless-stopped`, starts Ollama, enables/starts Kiro Crew, and verifies that the dashboard is reachable.

## Updates

From the checkout:

```bash
./update.sh
```

A successful update ends with explicit health checks for the Kiro Crew systemd service, the dashboard HTTP endpoint and the Ollama container. The updater also repairs execute permissions on the root helper scripts, so `./tool-smoke-test.sh` and `./acp-approval-smoke-test.sh` can be run directly.

The update entry point is transactional: it updates the checkout, refuses to silently downgrade an NVIDIA host when `nvidia-smi` is broken, cleanly stops running Crew/Ollama services, updates the Ollama runtime image, Kiro Crew stable channel, Goose stable channel and every installed Ollama model, reapplies ToolShim/grounding/language guardrails, restarts the stack, and verifies both the Ollama runtime and dashboard before reporting success. If an update step fails, it attempts to restore services that were running before the update.

## Architecture

```text
Kiro Crew managed service
        ↓ ACP
local kiro-cli compatibility shim
        ↓
Goose + ToolShim
        ↓
Ollama in Docker
        ↓
CPU / NVIDIA / AMD / Intel GPU
```

Kiro Crew's required `kirocrew` and `kirocrew-lite` modes are translated by the local ACP adapter. The main agent maps to Goose `approve`; the tool-less background `kirocrew-lite` mode maps to Goose `chat`.

On Ubuntu systems that restrict unprivileged user namespaces, the installer uses Kiro Crew's managed service so its narrow AppArmor `kirocrew-userns` profile can provide namespace sandboxing without globally weakening the kernel setting.

The sysadmin guardrails explicitly forbid fabricated command results: if a real tool result is unavailable, the agent must say that it could not inspect the machine rather than invent output.

## Persistent locations

The Git checkout is disposable. Runtime/configuration and durable data live outside it:

```text
~/.config/kiro-local/
~/.local/share/kiro-local/
```

This allows the source checkout to be updated or replaced without automatically deleting Crew/Goose persistent state.

## Compatibility note

The repository still contains the previous bundled v0.3.5 payload as a temporary fallback. The root-level launchers hide that packaging detail, so normal usage is already `git clone` → `./install.sh`. The bundle/bootstrap compatibility layer can be removed after this direct-clone path has been validated on the test machines.

## Safety

Keep initial execution conservative while testing:

```text
GOOSE_MODE=approve
CREW_APPROVAL_MODE=interactive
```

Start with read-only inspection, then test a disposable file operation, and only afterwards move on to service/autostart administration.

## Notes

- Docker Compose v2 is required on Linux.
- The NVIDIA driver must already work on the host (`nvidia-smi`) before NVIDIA Docker passthrough can be configured.
- Voice/STT is optional and is not required for text-based sysadmin operation.
- Windows support is experimental.
