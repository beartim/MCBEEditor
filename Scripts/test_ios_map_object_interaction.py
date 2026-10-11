#!/usr/bin/env python3
"""Compile the production hit/anchor methods with a minimal affine UIView fixture.

UIKit is unavailable on Linux. Only coordinate conversion and the popover data
holder are substituted; hit selection and menu anchoring come from the actual
WorldMapViewController source. This is a geometry regression, not a device UI test.
"""

from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def function(source: str, name: str) -> str:
    match = re.search(r"  (?:@objc )?private func " + re.escape(name) + r"\(", source)
    if not match:
        raise AssertionError(f"Production method missing: {name}")
    start = source.index("{", match.start())
    depth = 1
    cursor = start + 1
    while depth:
        if source[cursor] == "{":
            depth += 1
        elif source[cursor] == "}":
            depth -= 1
        cursor += 1
    return source[match.start():cursor].replace("private func", "func", 1)


def menu_tail(source: str, name: str) -> str:
    body = function(source, name)
    start = body.rfind("    if let popover = alert.popoverPresentationController")
    assert start >= 0, f"Missing popover binding in {name}"
    return body[start:body.rfind("    present(alert, animated: true)")]


def verify_source_routes(source: str) -> None:
    ui = function(source, "configureUI")
    tap = function(source, "mapTapped")
    assert "scrollView.addGestureRecognizer(mapTap)" in ui, "Tap gesture must cover the viewport, including marker pixels beyond the zoomed image"
    assert "imageView.addGestureRecognizer(mapTap)" not in ui, "Zoomed image must not restrict marker taps"
    assert tap.count("mapWorldObjectHit(at: imagePoint)") == 2, "Y and X/Z taps must share screen-space object selection"
    assert "imageView.bounds.contains(imagePoint)" in tap, "Tapping outside the map must not clamp to an edge block"
    assert "showWorldObjectDetails(hit)" in tap, "Object details must retain the selected marker's continuous coordinates"
    assert "showPlayerDetails(hit)" in tap and "showPlayerDetails(player)" in tap, "Player details must retain the selected star's coordinates"
    for name in ["showWorldObjectDetails", "showPlayerDetails"]:
        body = function(source, name)
        assert "configureMapObjectPopover(alert, localX: hit.localX, localZ: hit.localZ)" in body, f"{name} must bind the popover to its selected hit"
        assert "imageView.bounds.midX" not in body and "imageView.bounds.midY" not in body, f"{name} still anchors to the image midpoint"
    choice = function(source, "presentMapPointChoice")
    assert "showPlayerDetails(hit)" in choice, "Player overlap choice must retain the chosen star, not the original tap"
    print("PASS: viewport tap and production menu routing contracts (UIKit source audit only)")


def run(source_path: Path) -> None:
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise SystemExit("Swift compiler is required for iOS map geometry regression")
    source = source_path.read_text()
    shared = "private func mapWorldObjectHit(" in source
    if shared:
        methods = "\n".join(function(source, name) for name in (
            "mapObjectOverlayPoint", "mapWorldObjectHit", "configureMapPopover", "configureMapObjectPopover",
            "mapPlayerHits",
        ))
        object_hit = "return mapWorldObjectHit(at: point)"
        object_menu = player_menu = "configureMapObjectPopover(alert, localX: localX, localZ: localZ)"
    else:
        methods = "\n".join(function(source, name) for name in (
            "nearestWorldObject", "worldObjectDistance", "crossSectionWorldObjectHit",
            "mapPlayerHits",
        ))
        # These are the original mapTapped inputs: an integer block cell plus
        # 0.5, rather than the continuous gesture location.
        object_hit = """
        if axis != .y { return crossSectionWorldObjectHit(at: point) }
        let side = renderedSideChunks * 16
        let x = min(side - 1, max(0, Int(point.x / imageView.bounds.width * CGFloat(side))))
        let z = min(side - 1, max(0, Int(point.y / imageView.bounds.height * CGFloat(side))))
        return nearestWorldObject(localX: CGFloat(x) + 0.5, localZ: CGFloat(z) + 0.5)
        """
        object_menu = menu_tail(source, "showWorldObjectDetails")
        player_menu = menu_tail(source, "showPlayerDetails")

    fixture = r'''
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum MapSliceAxis { case x, y, z }
struct BedrockWorldObject { let stableID: String }
struct MapWorldObjectHit {
    let object: BedrockWorldObject
    let localX: CGFloat
    let localZ: CGFloat
    let isNormallyVisible: Bool
}
struct PlayerRecord { let displayName: String }
struct PlayerCoordinate { let record: PlayerRecord; let isLocal: Bool }
struct MapPlayerHit { let player: PlayerCoordinate; let localX: CGFloat; let localZ: CGFloat }

// The fixture models UIView's documented point conversion between an image
// with zoom/pan and a stationary viewport overlay. It has no hit-test logic.
class UIView {
    var bounds = CGRect(x: 0, y: 0, width: 768, height: 600)
    var scale: CGFloat = 1
    var translation = CGPoint.zero
    func convert(_ point: CGPoint, to other: UIView) -> CGPoint {
        CGPoint(x: (point.x * scale + translation.x - other.translation.x) / other.scale,
                y: (point.y * scale + translation.y - other.translation.y) / other.scale)
    }
    func layoutIfNeeded() {}
}
class UIPopoverPresentationController {
    var sourceView: UIView?
    var sourceRect = CGRect.zero
}
class UIAlertController {
    let popoverPresentationController: UIPopoverPresentationController? = UIPopoverPresentationController()
}

final class InteractionHarness {
    let view = UIView()
    let imageView = UIView()
    let objectOverlayView = UIView()
    var renderedSideChunks = 5
    var currentSliceAxis = MapSliceAxis.y
    var lastRenderedImage: String? = "rendered"
    var lastWorldObjectHits: [MapWorldObjectHit] = []
    var lastPlayerHits: [MapPlayerHit] = []
    var showPlayers = true
    __METHODS__
    func hit(at point: CGPoint, axis: MapSliceAxis) -> MapWorldObjectHit? {
        currentSliceAxis = axis
        __OBJECT_HIT__
    }
    func objectMenu(_ alert: UIAlertController, localX: CGFloat, localZ: CGFloat) {
        __OBJECT_MENU__
    }
    func playerMenu(_ alert: UIAlertController, localX: CGFloat, localZ: CGFloat) {
        __PLAYER_MENU__
    }
}

var failures: [String] = []
var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { failures.append(message) }
}
func close(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y) < 0.00001
}
func menuCenter(_ alert: UIAlertController, in overlay: UIView) -> CGPoint? {
    guard let popover = alert.popoverPresentationController, let source = popover.sourceView else { return nil }
    return source.convert(CGPoint(x: popover.sourceRect.midX, y: popover.sourceRect.midY), to: overlay)
}

let scales: [CGFloat] = [0.001, 0.01, 0.08, 0.25, 1, 4, 32, 256]
let axes: [MapSliceAxis] = [.y, .x, .z]
let canvases: [(Int, CGFloat)] = [(5, 32), (32, 8), (256, 0.5)]
for (chunks, pointsPerBlock) in canvases {
    for scale in scales {
        for axis in axes {
            let harness = InteractionHarness()
            harness.renderedSideChunks = chunks
            let size = CGFloat(chunks * 16) * pointsPerBlock
            harness.imageView.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            harness.imageView.scale = scale
            harness.objectOverlayView.translation = CGPoint(x: 12, y: 198)
            let icon = CGPoint(x: 95.25, y: 141.75)
            let local = CGPoint(x: 36.375, y: 47.25)
            let inImage = CGPoint(x: local.x * pointsPerBlock, y: local.y * pointsPerBlock)
            harness.imageView.translation = CGPoint(
                x: icon.x + harness.objectOverlayView.translation.x - inImage.x * scale,
                y: icon.y + harness.objectOverlayView.translation.y - inImage.y * scale)
            let note = "chunks=\(chunks), scale=\(scale), axis=\(axis)"

            for kind in ["entity", "blockEntity"] {
                let hit = MapWorldObjectHit(object: BedrockWorldObject(stableID: kind),
                    localX: local.x, localZ: local.y, isNormallyVisible: true)
                harness.lastWorldObjectHits = [hit]
                // Test the visible glyph and finger tolerance at fixed screen
                // distances, independently of zoom and the raster canvas.
                for offset in [CGFloat(0), 3, 5, 12, 17] {
                    let point = CGPoint(x: inImage.x + offset / scale, y: inImage.y)
                    check(harness.hit(at: point, axis: axis)?.object.stableID == kind,
                          "Visible \(kind) missed at \(offset) screen points; \(note)")
                }
                check(harness.hit(at: CGPoint(x: inImage.x + 19 / scale, y: inImage.y), axis: axis) == nil,
                      "Far tap selected \(kind) outside its screen hit radius; \(note)")
                let hidden = MapWorldObjectHit(object: BedrockWorldObject(stableID: "hidden"),
                    localX: local.x, localZ: local.y, isNormallyVisible: false)
                harness.lastWorldObjectHits = [hidden, hit]
                check(harness.hit(at: inImage, axis: axis)?.object.stableID == kind,
                      "Hidden marker stole the tap; \(note)")
                let alert = UIAlertController()
                harness.objectMenu(alert, localX: local.x, localZ: local.y)
                check(menuCenter(alert, in: harness.objectOverlayView).map { close($0, icon) } ?? false,
                      "\(kind) menu arrow targets map center instead of marker; \(note)")
            }

            for isLocal in [true, false] {
                harness.lastPlayerHits = [MapPlayerHit(player: PlayerCoordinate(
                    record: PlayerRecord(displayName: isLocal ? "Local" : "Online"), isLocal: isLocal),
                    localX: local.x, localZ: local.y)]
                let playerTap = CGPoint(x: inImage.x + 7 / scale, y: inImage.y)
                check(harness.mapPlayerHits(at: playerTap).count == 1, "Player star missed; \(note)")
                check(harness.mapPlayerHits(at: CGPoint(x: inImage.x + 16 / scale, y: inImage.y)).isEmpty,
                      "Player hit radius grew with zoom; \(note)")
                let alert = UIAlertController()
                harness.playerMenu(alert, localX: local.x, localZ: local.y)
                check(menuCenter(alert, in: harness.objectOverlayView).map { close($0, icon) } ?? false,
                      "Player menu arrow targets map center instead of star; \(note)")
            }
            harness.lastWorldObjectHits = []
            check(harness.hit(at: inImage, axis: axis) == nil, "Empty map selected an object; \(note)")
            harness.lastWorldObjectHits = [
                MapWorldObjectHit(object: BedrockWorldObject(stableID: "first"),
                    localX: local.x, localZ: local.y, isNormallyVisible: true),
                MapWorldObjectHit(object: BedrockWorldObject(stableID: "closest"),
                    localX: local.x + 10 / (pointsPerBlock * scale), localZ: local.y,
                    isNormallyVisible: true),
            ]
            check(harness.hit(at: CGPoint(x: inImage.x + 10 / scale, y: inImage.y), axis: axis)?.object.stableID == "closest",
                  "Nearby markers selected a quantized block cell instead of the closest glyph; \(note)")
        }
    }
}

// After panning near each viewport corner, anchoring must still use the
// stationary overlay and the actual marker location, not the image midpoint.
for icon in [CGPoint(x: 1.5, y: 1.5), CGPoint(x: 766.5, y: 1.5),
             CGPoint(x: 1.5, y: 598.5), CGPoint(x: 766.5, y: 598.5)] {
    let harness = InteractionHarness()
    harness.imageView.bounds = CGRect(x: 0, y: 0, width: 2560, height: 2560)
    harness.imageView.scale = 0.08
    let local = CGPoint(x: 48.5, y: 32.5)
    harness.imageView.translation = CGPoint(x: icon.x - local.x * 32 * 0.08,
                                           y: icon.y - local.y * 32 * 0.08)
    let alert = UIAlertController()
    harness.objectMenu(alert, localX: local.x, localZ: local.y)
    check(menuCenter(alert, in: harness.objectOverlayView).map { close($0, icon) } ?? false,
          "Panned corner anchor drifted: \(icon)")
}
for (icon, expected) in [
    (CGPoint(x: -4, y: 100), CGPoint(x: 0.5, y: 100)),
    (CGPoint(x: 772, y: 100), CGPoint(x: 767.5, y: 100)),
    (CGPoint(x: 100, y: -4), CGPoint(x: 100, y: 0.5)),
    (CGPoint(x: 100, y: 604), CGPoint(x: 100, y: 599.5)),
] {
    let harness = InteractionHarness()
    harness.imageView.bounds = CGRect(x: 0, y: 0, width: 2560, height: 2560)
    harness.imageView.scale = 0.08
    let local = CGPoint(x: 48.5, y: 32.5)
    harness.imageView.translation = CGPoint(x: icon.x - local.x * 32 * 0.08,
                                           y: icon.y - local.y * 32 * 0.08)
    let alert = UIAlertController()
    harness.objectMenu(alert, localX: local.x, localZ: local.y)
    check(menuCenter(alert, in: harness.objectOverlayView).map { close($0, expected) } ?? false,
          "Partially clipped marker must anchor to its visible edge: \(icon)")
    check(alert.popoverPresentationController.map { harness.objectOverlayView.bounds.contains($0.sourceRect) } ?? false,
          "Clipped marker produced an offscreen sourceRect")
}
if !failures.isEmpty {
    for failure in failures.prefix(16) { print("FAIL: \(failure)") }
    print("FAILED: \(failures.count) of \(checks) production map hit/anchor checks")
    exit(1)
}
print("PASS: \(checks) production map hit/anchor checks; 8 zoom scales, Y/X/Z, 3 canvas densities, entity/block entity/local and online player, hidden markers and panned corners")
'''
    fixture = (fixture.replace("__METHODS__", methods)
               .replace("__OBJECT_HIT__", object_hit)
               .replace("__OBJECT_MENU__", object_menu)
               .replace("__PLAYER_MENU__", player_menu))
    with tempfile.TemporaryDirectory(prefix="mcbe-ios-map-hit-") as temp:
        swift = Path(temp) / "main.swift"
        binary = Path(temp) / "map-interaction-tests"
        swift.write_text(fixture)
        subprocess.run([swiftc, str(swift), "-o", str(binary)], check=True)
        result = subprocess.run([str(binary)])
        if result.returncode:
            raise SystemExit(result.returncode)
    verify_source_routes(source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Sources/UI/WorldMapViewController.swift")
    run(parser.parse_args().source)
