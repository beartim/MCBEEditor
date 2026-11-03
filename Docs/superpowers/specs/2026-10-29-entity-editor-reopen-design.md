# Entity NBT reopen after Save

The map selection list must reopen the NBT actually committed by Save without
requiring the user to dismiss and repeat the selection. Existing viewed badges
are presentation state and must not select an older document.

The current list keeps immutable scanned objects, and each editor initializes
its document from that snapshot. The store already commits and rebinds the
saved object, but the callback discards that rebound object.

Use the existing save callback to publish the rebound object (nil after deletion
or an unresolved committed save). Replace the selected row in the map selection
and village resident snapshot lists, preserve its viewed state, and reapply the
current search. Keep moved objects in that original selection snapshot so the
user can reopen them. Remove deleted/unresolvable rows instead of offering an
obsolete editable snapshot. Existing browser/map refresh notifications continue.

Each list row has a private UUID independent of scanner storage identity. Keep
that UUID through saves/moves and use it for callbacks and viewed badges. Legacy
root indexes shift after deleting/moving siblings and cannot identify UI rows.

Make editor initialization read the selected document through the existing
identity-aware store. Reading failures prevent opening an editable stale copy;
all four callers display an error. No asynchronous refresh may replace dirty
edits. Failed saves must not update the list or publish success.

Retain iOS 13.0, marketing version 1.0.0, current storage encodings and all prior
command/catalog changes. No new dependencies or Windows behavior changes.

Verify real list action callbacks and editor initialization/save/delete methods
with production scanner/store/codecs. Linux substitutes UIKit presentation and
the LevelDB boundary; this is not an iOS device test. Cover actorprefix, legacy
consecutive records, block entities, changes to identity/location, read/save
failures, current search and viewed badges, and preservation of sibling roots.
