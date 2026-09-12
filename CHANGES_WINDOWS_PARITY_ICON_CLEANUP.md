# Windows parity / icon / cleanup

- Synced iOS NBT Compound insertion conflict handling: overwrite / keep / cancel.
- Empty imported root names alone receive generated unique names; real duplicate names are no longer silently renamed.
- Generated a transparent-background Windows icon from the current iOS AppIcon artwork and embedded it in both the WPF payload and the final portable launcher EXE.
- Removed duplicated UI-level silent texture-reload guards; the texture store now owns the non-fatal reload behavior and preserves the last successful overrides when the directory cannot be enumerated.
- Re-audited Windows porting compatibility code. MCBEEditor-version migration shims remain removed; Bedrock-format compatibility code remains intentionally intact.
