# Windows build/self-test fix — ticking-area test isolation

- Isolated the chunk-query `Ticking=True` fixture from the structured ticking-area manager fixture by giving the manager its own `SelfTestWorldDatabase`.
- This prevents the earlier `SelfTest` ticking area from leaking into the manager test and changing the expected area count from two to three.
- Updated the Windows ticking-area manager UI to call the current `TickingAreas()` API. The obsolete `TickingAreas(false)` call belonged to the removed editor-version compatibility path.
- No production ticking-area persistence format or `chunk query` `Ticking=True/False` semantics were changed.
