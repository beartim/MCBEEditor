# Shared Commands / Command.txt batch execution

- Textures/ReadMe.txt now uses the exact user-provided wording for the current PNG/colors.txt override format.
- App launch creates Documents/Commands and atomically regenerates Commands/ReadMe.txt.
- Commands/ReadMe.txt embeds `WorldCommandParser.helpText()` so its supported-command section always matches the in-app `help` output.
- MCBEEditor never creates, overwrites, or deletes Commands/Command.txt.
- Entering a world checks a non-empty Commands/Command.txt once per workspace and asks whether to execute it.
- After confirmation every non-empty line is parsed first. Any syntax error rejects the entire batch before `WorldCommandExecutor` is called.
- Syntax diagnostics preserve original 1-based Command.txt line numbers.
- A blocking busy overlay is displayed for validation and execution; the workspace is non-interactive while the batch is running.
- Any in-flight map render is cancelled immediately before command execution to avoid concurrent map reads during LevelDB mutation.
- Valid commands execute serially through the existing `WorldCommandExecutor`.
- Runtime failures are recorded for the affected line and later commands continue.
- Every source command and its styled result/error is appended to the existing command terminal for later review.
- World mutation notification is sent once after the complete batch.
