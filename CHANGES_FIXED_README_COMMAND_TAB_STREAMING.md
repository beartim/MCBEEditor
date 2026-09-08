# Fixed ReadMe / Command.txt command-tab streaming update

- `Textures/ReadMe.txt` is now held as one fixed source string and continues to be restored verbatim on launch / activation.
- `Commands/ReadMe.txt` is now a fixed source string containing the current command help output. It no longer interpolates `WorldCommandParser.helpText()` at runtime.
- Commands ReadMe synchronization is versioned with `readMeRevision`; it is rewritten only when missing or when the embedded command-set revision changes after a software command update.
- If `Documents/Commands/Command.txt` exists, entering a world selects the Commands tab before the workspace is shown. An empty Command.txt still opens the Commands tab but does not prompt for execution.
- Command.txt still performs a complete syntax preflight before any command executes. Any syntax error prevents the entire batch.
- During batch execution there is no execution loading overlay. The Commands terminal remains visible and scrollable.
- Each Command.txt source line is appended to the terminal immediately, its execution result is appended immediately afterward, and only then does the next command start.
- While a Command.txt batch is running, other bottom tabs, workspace close buttons and interactive modal dismissal are disabled. They are restored after the batch ends.
- Manual command input remains disabled by the command controller's existing running state during the batch.
