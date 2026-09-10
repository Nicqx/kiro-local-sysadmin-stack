# Kiro Local Sysadmin Stack v0.3.5

## Quick install from GitHub

Clone the repository and run the installer as your normal login user (**do not run the installer with `sudo`**):

```bash
git clone https://github.com/Nicqx/kiro-local-sysadmin-stack.git
cd kiro-local-sysadmin-stack
./scripts/install.sh
```

For a complete reset/reinstall of an earlier test version:

```bash
./scripts/full-reset-install.sh
```

To update the installer source later:

```bash
git pull
```

> The stack keeps its runtime/configuration and persistent Crew/Goose/Ollama data outside the Git checkout under `~/.config/kiro-local/` and `~/.local/share/kiro-local/`.

## v0.3.5 Linux managed-service compatibility

Linux now uses Kiro Crew's official system service rather than the older project user unit. This lets Kiro Crew install its narrow AppArmor `userns` profile on Ubuntu 23.10+ while the gateway still runs as the normal login user. The installer removes group/world write permissions from the private Crew launcher path before service installation, writes a systemd drop-in carrying the local Goose/Ollama environment, and materializes both required Crew agent specs (`kirocrew` and `kirocrew-lite`).

The local ACP adapter exposes Crew-owned `kirocrew*` modes to the Crew runtime. `kirocrew-lite` maps to Goose `chat` (tool-less background work); primary/other Crew modes map to the configured `GOOSE_MODE` (default `approve`).

For an existing v0.3.3 test install, repair in place:

```bash
./scripts/repair-v033.sh
```

> **v0.3.5 safety rule:** never run the installer with `sudo`. Run it as your normal login user. The scripts invoke sudo internally only for targeted system operations and cleanup of root-owned Ollama bind-mount files.

### v0.3.5 recovery fixes

- refuses root/sudo execution, preventing accidental `/root` installs;
- removes project-specific `/root` residue left by an older accidental sudo run;
- safely deletes root-owned Ollama model files during full reset;
- checks the logged-in user's `systemd --user` bus before installation;
- creates Crew's config paths before `setup --agent-only`;
- exposes the local compatibility shim as `kiro-cli` during Crew setup.

## Recommended clean install / replacing v0.3.x

For a completely blank reinstall (old stack + history/memory/models removed), run:

```bash
git clone https://github.com/Nicqx/kiro-local-sysadmin-stack.git
cd kiro-local-sysadmin-stack
./scripts/full-reset-install.sh
```

The script asks you to type `RESET`. Before deleting durable state it creates a lightweight backup under `~/kiro-local-backups/` (Crew/Goose/workspace/config; Ollama model blobs are intentionally not backed up). It also stops/disables a host-native `ollama.service` so Docker can own port 11434. Docker, GPU drivers and NVIDIA Container Toolkit are left installed.

If you want a clean runtime/config reinstall but **keep** history, memory and downloaded models:

```bash
./scripts/fresh-install.sh --disable-native-ollama
```

New in v0.3.5: port 11434 conflicts fail explicitly instead of causing a false GPU→CPU fallback; `chat.sh` and `crew.sh` load the stack runtime environment automatically.

---

Experimental fully-local sysadmin-agent stack:

- **Kiro Crew**: dashboard, persistent sessions/memory/lessons
- **Goose ACP**: local agent/tool execution layer
- **Ollama**: local LLM inference
- **ACP compatibility shim**: makes Crew's Kiro-flavoured ACP expectations work with Goose
- **Auto model selection**: chooses a local model based on machine memory and validates that it can actually load

The integration **Kiro Crew -> custom ACP shim -> Goose -> Ollama is experimental**. Kiro Crew does not currently ship an official Ollama provider for this exact architecture.

## Data persistence

Linux defaults:

- config: `~/.config/kiro-local/`
- persistent data: `~/.local/share/kiro-local/`

Windows uses the same locations below `%USERPROFILE%`:

- `%USERPROFILE%\.config\kiro-local\`
- `%USERPROFILE%\.local\share\kiro-local\`

Crew history, lessons, memory and Goose state are outside the installer directory, so rebuilding/reinstalling the runtime does not delete them unless you explicitly purge them.

---

# Automatic Ollama model selection

The machine-specific config is:

```text
~/.config/kiro-local/stack.env
```

Default:

```text
OLLAMA_MODEL=auto
OLLAMA_AUTO_PROFILE=largest
OLLAMA_AUTO_RESERVE_GB=0
OLLAMA_AUTO_SMOKE_TEST=1
OLLAMA_AUTO_REMOVE_FAILED=1
```

`OLLAMA_MODEL=auto` means:

1. Detect physical RAM.
2. Use validated GPU VRAM when Linux passthrough/native GPU access is available.
3. Keep memory reserved for the OS/Crew/Goose.
4. Read the editable model ladder.
5. Choose the largest curated agent-capable model expected to fit.
6. Pull it.
7. Run a one-token smoke test.
8. If the model cannot load reliably, remove it (optional) and step down automatically.

The selected model is cached in:

```text
~/.config/kiro-local/model.env
```

The hardware-selection report is:

```text
~/.config/kiro-local/hardware.json
```

Force a new hardware selection:

Linux:

```bash
./scripts/reselect-model.sh
./scripts/restart.sh
```

Windows:

```powershell
.\windows\reselect-model.ps1
.\windows\restart.ps1
```

## Model ladder

Editable after first run:

```text
~/.config/kiro-local/model-ladder.json
```

The default `largest` ladder currently contains:

```text
qwen3:0.6b
qwen3:1.7b
qwen3:4b
qwen3:8b
qwen3:14b
gpt-oss:20b
qwen3-coder:30b
gpt-oss:120b
```

This is deliberately a **curated ladder**, not a scan of every Ollama model. "Largest" therefore means the strongest/largest model in this list that the memory budget says should fit.

If you want only Qwen models, or different thresholds, edit `model-ladder.json`.

To pin a model and completely disable automatic selection:

```text
OLLAMA_MODEL=qwen3:8b
```

# Linux GPU acceleration (v0.3.5)

The Linux installer now detects and configures Docker GPU acceleration for Ollama.

Machine config:

```text
OLLAMA_GPU=auto
OLLAMA_GPU_INSTALL_NVIDIA_TOOLKIT=1
OLLAMA_GPU_VERIFY=1
```

Modes:

- `auto`: try supported GPU acceleration and fall back to CPU if runtime verification fails.
- `force`: require GPU acceleration. Installation/start fails rather than silently using CPU.
- `off`: CPU only.

Detection order:

1. NVIDIA + working `nvidia-smi` -> NVIDIA Container Toolkit + Docker GPU reservation.
2. AMD + `/dev/kfd` + `/dev/dri` -> ROCm Ollama image.
3. AMD with `/dev/dri`, or Intel with `/dev/dri` -> Vulkan device passthrough.
4. Otherwise -> CPU.

For NVIDIA on Ubuntu/Debian, when `OLLAMA_GPU_INSTALL_NVIDIA_TOOLKIT=1`, the installer may use `sudo` to install/configure NVIDIA Container Toolkit and restart Docker. The NVIDIA driver itself is **not** installed by this package: `nvidia-smi` must already work on the host.

GPU configuration is persisted in:

```text
~/.config/kiro-local/gpu.env
~/.config/kiro-local/gpu.json
~/.config/kiro-local/docker-compose.gpu.yml
```

Inspect it at any time:

```bash
./scripts/gpu-status.sh
```

Re-detect/reconfigure after a driver, VM passthrough or hardware change:

```bash
./scripts/reconfigure-gpu.sh
```

After loading the model, the stack checks `ollama ps`. A `100% GPU` or CPU/GPU split is accepted as GPU acceleration. With `OLLAMA_GPU=force`, `100% CPU` is an error.

### Virtual machines

A virtual machine can use the physical GPU only if the hypervisor exposes a real compute-capable GPU/device to the guest. A generic VirtualBox/VMware/virtio/QXL display adapter is not treated as Ollama GPU acceleration. In that case `gpu-status.sh` reports the guest limitation and `auto` falls back to CPU; `force` fails.

### GPU-specific knobs

NVIDIA:

```text
OLLAMA_GPU_NVIDIA_VISIBLE=all
```

This can later be restricted to a GPU index or preferably a stable GPU UUID.

AMD:

```text
OLLAMA_GPU_AMD_BACKEND=auto
OLLAMA_GPU_AMD_VISIBLE=
OLLAMA_GPU_AMD_HSA_OVERRIDE=
```

Set `OLLAMA_GPU_AMD_BACKEND=vulkan` to bypass ROCm and test the Vulkan backend.

Vulkan mixed iGPU/dGPU systems:

```text
OLLAMA_GPU_VULKAN_VISIBLE=
```

Set a device index if Ollama chooses the wrong Vulkan GPU.

When GPU passthrough has been configured, the automatic model selector may use validated GPU VRAM in addition to host RAM. The one-token smoke test is still the final model-fit check.

### Windows GPU note

Windows uses **native Ollama**, so native Ollama can use supported GPU acceleration directly. The selector can take detected NVIDIA VRAM into account, and the smoke test remains the final authority.

---

# Linux / Ubuntu install

## Requirements

```bash
docker --version
docker compose version
python3 --version
curl --version
```

`python` is not required. `python3` is correct.

Docker Compose **v2** is required (`docker compose`, not the old `docker-compose`).

## Install

```bash
git clone https://github.com/Nicqx/kiro-local-sysadmin-stack.git
cd kiro-local-sysadmin-stack
./scripts/install.sh
```

Installation will:

1. Create the persistent directories.
2. Auto-select an Ollama model if configured.
3. Install Kiro Crew into an isolated runtime.
4. Install Goose.
5. Start Ollama in Docker.
6. Pull and smoke-test the selected model.
7. Install the local ACP compatibility layer.
8. Start Crew as a user systemd service.

## Start / stop

```bash
./scripts/start.sh
./scripts/stop.sh
./scripts/restart.sh
./scripts/status.sh
```

Logs:

```bash
./scripts/logs.sh
./scripts/logs.sh ollama
```

Diagnostics:

```bash
./scripts/doctor.sh
./scripts/doctor.sh --deep
./scripts/gpu-status.sh
```

Reconfigure GPU detection without reinstalling:

```bash
./scripts/reconfigure-gpu.sh
```

Dashboard token:

```bash
./scripts/token.sh
./scripts/token.sh 8h
```

Dashboard:

```text
http://127.0.0.1:5476
```

---

# Windows 10/11 x64 support (experimental package layer)

Kiro Crew, Kiro CLI, Goose and Ollama now have native Windows support. The custom local integration in this package uses that native support instead of trying to run the host sysadmin agent inside Docker.

Why native?

If Crew/Goose ran inside a Linux Docker container on Windows, commands such as Windows process inspection, registry access, services and local files would target the container/VM boundary rather than the Windows host. Native execution is the correct architecture for a Windows sysadmin agent.

## Windows prerequisites

Recommended:

- Windows 10/11 x64
- real CPython 3.12 (`py -3.12`)
- PowerShell
- Internet access for the initial installation/model downloads

The installer can install native Ollama and Goose automatically if missing.

## Install from PowerShell

Extract the ZIP, open PowerShell in the extracted directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\install.ps1
```

The Windows installer:

1. Creates a dedicated Kiro Crew Python virtual environment.
2. Installs Kiro Crew from its release feed.
3. Installs native Ollama if missing and allowed by config.
4. Installs native Goose if missing and allowed by config.
5. Auto-selects and smoke-tests the local model.
6. Installs the ACP compatibility shim.
7. Starts the Crew gateway.
8. Optionally creates a current-user `KiroLocalCrew` Scheduled Task for logon startup.

## Windows start / stop

```powershell
.\windows\start.ps1
.\windows\stop.ps1
.\windows\restart.ps1
.\windows\status.ps1
```

Diagnostics:

```powershell
.\windows\doctor.ps1
.\windows\doctor.ps1 -Deep
```

Token:

```powershell
.\windows\token.ps1
.\windows\token.ps1 -Ttl 8h
```

Uninstall runtime but keep history/memory:

```powershell
.\windows\uninstall.ps1
```

Purge the stack's own persistent data/config:

```powershell
.\windows\uninstall.ps1 -Purge
```

The purge command intentionally does **not** uninstall system-wide Ollama or Goose.

## Windows limitations

The Windows scripts are an experimental wrapper around upstream native components and were not executable-tested on a real Windows machine in the environment where this package was generated. The Python/common logic and Linux scripts have static tests, but the first Windows machine should be treated as an integration test.

Windows-specific sysadmin permissions also differ from Linux:

- normal commands run as the logged-in user;
- operations requiring Administrator rights still require Windows elevation/UAC;
- `systemctl`/`journalctl` concepts become Windows Services/Event Log/PowerShell equivalents;
- GUI-user-session administration works better natively than through Docker/WSL.

---

# Machine-specific tuning

Main config:

```text
~/.config/kiro-local/stack.env
```

Important parameters:

```text
OLLAMA_MODEL=auto
OLLAMA_AUTO_PROFILE=largest
GOOSE_CONTEXT_LIMIT=32768
GOOSE_MAX_TURNS=50
GOOSE_MODE=approve
CREW_APPROVAL_MODE=interactive
CREW_SANDBOX=off
CREW_BIND=127.0.0.1
CREW_PORT=5476
```

Sysadmin behaviour/guardrails:

```text
~/.config/kiro-local/sysadmin-guardrails.md
```

Keep `GOOSE_MODE=approve` while validating the stack. Do not enable unrestricted automatic destructive administration until the agent/tool path has been tested on that particular machine.

---

# Suggested first test

Do not start with a modification. Ask:

```text
Inspect this machine and tell me whether Conky is currently running.
Do not change anything. Actually use the available tools and show which checks you performed.
```

Then try a controlled change such as creating a disposable file in a test directory, verify it, and remove it.

Only after tool execution is proven should you test service/autostart configuration.

## v0.3.5 and earlier fixes

v0.3.5 adds a clean-reset installer, explicit port-conflict detection, and automatically loads the runtime environment in `chat.sh` / `crew.sh`.

v0.3.1 fixed two v0.3.0 integration bugs:

- the Ollama smoke test no longer unloads the model before GPU verification; GPU verification now checks `/api/ps` and `size_vram`;
- the Goose ACP adapter advertises the `kirocrew` compatibility mode expected by Crew and the installer runs `kirocrew setup --agent-only` automatically.

The old `repair-v030.sh` remains for reference, but for the current test phase a clean reinstall is recommended:

```bash
./scripts/full-reset-install.sh
```

Interactive CLI chat:

```bash
./scripts/chat.sh
```

Any Kiro Crew CLI command without modifying PATH:

```bash
./scripts/crew.sh doctor
./scripts/crew.sh logs -f
```

## v0.3.5 managed-service recovery fix

The official `kirocrew service install` command already starts the managed system service. v0.3.4 restarted it again immediately, and repeated repair/install runs could trip systemd start-rate limiting (`start request repeated too quickly`). v0.3.5 resets stale failure counters and avoids the redundant restart.

Recovery without reinstalling models or data:

```bash
./scripts/recover-crew.sh
```

If the service has a genuine startup failure, the recovery script prints the recent `journalctl` log instead of repeatedly restarting it.
