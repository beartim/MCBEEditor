# Entity NBT reopen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Reopening an entity from the same list after Save displays committed NBT.

**Architecture:** Publish the store's rebound saved object to snapshot list owners.
Read current NBT when constructing the editor and report identity/read errors.

**Tech Stack:** Swift, UIKit, existing Bedrock codecs and storage, Python harness.

**Spec:** `docs/superpowers/specs/2026-10-29-entity-editor-reopen-design.md`

## Global Constraints

- Retain iOS 13.0 and marketing version 1.0.0.
- No new dependencies or Windows behavior changes.
- Preserve existing command/catalog changes and storage encodings.
- Failed reads/saves must not allow stale writes or publish success.

## Review Focus

- UniqueID changes retain the correct actor key and reopen the saved root.
- Legacy moves shift sibling indexes without editing a different root.
- Active search and viewed state reflect the rebound object.
- Deleted or unresolved committed objects cannot open an obsolete snapshot.
- Save failure leaves the persisted data and list snapshot unchanged.

### Task 1: Refresh saved list objects and editor input

**Files:**
- Modify: `Sources/UI/WorldObjectNBTEditorViewController.swift`
- Create: `Sources/UI/WorldObjectListItem.swift`
- Modify: `Sources/UI/MapSelectionResultsViewController.swift`
- Modify: `Sources/UI/VillageResidentEntitiesViewController.swift`
- Modify: `Sources/UI/EntityBrowserViewController.swift`
- Modify: `Sources/UI/WorldMapViewController.swift`
- Test: `Scripts/test_entity_editor_reopen.py`
- Modify: `Scripts/run_core_tests.sh`

**Interfaces:**
- Consumes: `BedrockWorldObjectNBTStore.document(for:)`, `save`, `refreshedObject`.
- Produces: throwing editor initializer and `onSave: (BedrockWorldObject?) -> Void`; snapshot rows carry a private UUID independent of storage indexes.

- [x] Add a behavioral harness running the actual map list and extracted editor
  initializer/save/delete bodies with real store/scanner/codecs.
- [x] Run the harness against the original source; observe the stale NBT failure.
- [x] Read current NBT in the initializer; publish saved objects; update list
  snapshots, filters and viewed state; handle throws at every call site.
- [x] Pass reopen/second-save, moved identities, siblings, search, deletion and
  read/write failure scenarios for all three storage types.
- [x] Run `Scripts/run_core_tests.sh`, parse changed UIKit files, review the full
  diff, and package the complete source. This source archive has no Git history;
  compare every file against the original ZIP rather than committing.
