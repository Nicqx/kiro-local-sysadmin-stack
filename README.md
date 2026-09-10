# Kiro Local Sysadmin Stack v0.3.5

Experimental fully-local sysadmin-agent stack built from:

- Kiro Crew — dashboard, sessions, memory and orchestration
- Goose ACP — local agent/tool execution
- Ollama — local LLM inference
- a local ACP compatibility adapter between Kiro Crew and Goose

The current Linux package includes automatic Ollama model selection, NVIDIA/AMD/Intel GPU detection, Docker GPU passthrough, Kiro Crew managed-service/AppArmor setup, clean reset/reinstall helpers and diagnostics. Windows support is experimental.

## Quick install from GitHub

Run the installer as your normal login user. **Do not run the whole installer with `sudo`.**

```bash
git clone https://github.com/Nicqx/kiro-local-sysadmin-stack.git
cd kiro-local-sysadmin-stack
bash ./bootstrap.sh
unzip kiro-local-sysadmin-stack-v0.3.5.zip
cd kiro-local-sysadmin-stack-v0.3.5
./scripts/install.sh
```

`bootstrap.sh` reconstructs the v0.3.5 package stored in this repository and verifies its SHA-256 before accepting it.

Expected package checksum:

```text
e3cb9343e626b2cdf82a5a1e06552e5b4edec19dd916c4b2d13403b0611954e5
```

## Completely clean reinstall

If you are replacing one of the test versions and want to remove the stack-owned runtime, configuration, history/memory and downloaded Ollama models first:

```bash
./scripts/full-reset-install.sh
```

The script asks you to type `RESET`. It may request `sudo` internally for specific system operations, but the script itself must be started as the normal login user.

## Keep persistent data and reinstall runtime/config

```bash
./scripts/fresh-install.sh --disable-native-ollama
```

## Common commands

```bash
./scripts/status.sh
./scripts/gpu-status.sh
./scripts/doctor.sh --deep
./scripts/chat.sh
./scripts/token.sh 8h
./scripts/recover-crew.sh
```

Local dashboard:

```text
http://127.0.0.1:5476
```

## Update the repository copy

```bash
git pull
```

When a newer package version is published here, the README/bootstrap version will be updated with it.

## Current v0.3.5 integration state

The package currently uses this Linux architecture:

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

On Ubuntu versions with restricted unprivileged user namespaces, the installer uses Kiro Crew's managed service so its narrow AppArmor `kirocrew-userns` profile can provide namespace sandboxing without globally weakening the kernel setting.

## Persistent locations

The checkout itself is disposable. Runtime/configuration and durable data live outside it:

```text
~/.config/kiro-local/
~/.local/share/kiro-local/
```

This allows the installer source to be replaced or updated without automatically deleting Crew/Goose persistent state.

## Safety

Keep the initial execution mode conservative while testing:

```text
GOOSE_MODE=approve
CREW_APPROVAL_MODE=interactive
```

Start with read-only system inspection, then test a disposable file operation, and only afterwards move on to service/autostart administration.

## Notes

- Docker Compose v2 is required on Linux.
- The NVIDIA driver must already work on the host (`nvidia-smi`) before NVIDIA Docker passthrough can be configured.
- Windows support is an experimental package layer and should be treated as an integration test on the first Windows machine.
- Voice/STT is optional and is not required for text-based sysadmin operation.
