# Tool-call grounding note

The local sysadmin agent must never treat planned shell commands as executed commands.

For the Ollama profile, the repository enables Goose ToolShim because smaller local models can emit tool intent as prose without a valid structured tool call. ToolShim converts such intent into Goose tool calls using a structured interpreter pass.

Use `./tool-smoke-test.sh` after install/update. It creates an unpredictable nonce in a temporary file and passes only if Goose obtains that nonce through a real developer/shell tool read.

If this smoke test fails, do not trust machine-state answers from the agent, even when they are phrased as command output.
