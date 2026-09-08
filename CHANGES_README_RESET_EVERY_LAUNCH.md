# ReadMe reset on every launch

- Removed the Commands ReadMe command-set revision marker and UserDefaults revision tracking.
- `Documents/Commands/ReadMe.txt` is now atomically rewritten from the fixed source text every app launch.
- `Documents/Textures/ReadMe.txt` remains fixed source text and is also written during app launch (and texture reload activation paths).
- `Commands/Command.txt` is never created, overwritten, or deleted by MCBEEditor.
- Existing Command.txt tab switching, syntax preflight, streaming execution, and navigation locking behavior is unchanged.
