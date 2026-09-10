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

## Updates

From the checkout:

```bash
./update.sh
```

The update entry point performs a fast-forward-only `git pull` and then runs the stack updater.

## Architecture

```text
Kiro Crew managed service
        ↓ ACP
local kiro-cli compatibility shim
        ↓
Goose
        ↓
Ollama in Docker
        ↓
CPU / NVIDIA / AMD / Intel GPU
```

Kiro Crew's required `kirocrew` and `kirocrew-lite` modes are translated by the local ACP adapter. The main agent maps to Goose `approve`; the tool-less background `kirocrew-lite` mode maps to Goose `chat`.

On Ubuntu systems that restrict unprivileged user namespaces, the installer uses Kiro Crew's managed service so its narrow AppArmor `kirocrew-userns` profile can provide namespace sandboxing without globally weakening the kernel setting.

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
