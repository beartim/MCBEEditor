# Windows build fix — EnvironmentCommandStore SelfTest constructor

The chunk-query self-test still instantiated `EnvironmentCommandStore` with the obsolete one-argument form after the store had been changed to require both a `WorldDocument` and an `IWorldDatabase`.

Fixed the self-test to create a temporary `WorldDocument` and pass `(document, database)` when creating the test ticking area. Production command code and the `IsSlimeChunk` / `Ticking` output semantics are unchanged.

A repository-wide scan confirms that every `EnvironmentCommandStore(...)` construction now supplies both required arguments.
