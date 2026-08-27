# iPhone text fitting and map interaction stability

- Added compact single-line text support for built-in table-cell labels so narrow iPhone layouts shrink text before showing an ellipsis.
- Applied a smaller segmented-control title font on iPhone only; iPad typography is unchanged.
- Added compact title handling to dense map/selection/entity-range buttons.
- Stopped map rendering from starting while UIScrollView is tracking, dragging, decelerating, or zooming.
- Cancelled and detached in-flight map renders as soon as a new user pan/pinch begins, preventing an old render from restoring a stale viewport anchor after the user has moved elsewhere.
- Disabled elastic scroll/zoom bounce because virtual map insets already provide panning room and bounce velocity could be amplified when a newly rendered canvas changed size.
- Changed infinite-zoom handling so minimum/maximum zoom bounds are widened once when a pinch begins instead of being mutated on every `scrollViewDidZoom` callback.
- Custom selection pan/pinch gestures use the same render-cancellation and stable zoom-range behavior.
- Added `Scripts/test_phone_text_map_stability.sh` regression checks.

Version remains 1.0.0 (build 100).
