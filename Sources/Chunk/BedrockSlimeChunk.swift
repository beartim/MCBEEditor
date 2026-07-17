import Foundation

/// Bedrock Edition slime-chunk calculation used by the original Android
/// Blocktopograph renderer:
/// https://github.com/oO0oO0oO0o0o00/blocktopograph/blob/master/app/src/main/java/com/mithrilmania/blocktopograph/map/renderer/SlimeChunkRenderer.java
///
/// The MCPE calculation was reverse engineered by @protolambda and @jocopa3.
/// Unlike Java Edition, the world seed is not part of the calculation: only
/// the signed chunk X/Z coordinates are mixed into the MT19937 seed.
enum BedrockSlimeChunk {
    static func isSlimeChunk(x: Int32, z: Int32) -> Bool {
        let unsignedX = UInt64(UInt32(bitPattern: x))
        let unsignedZ = UInt64(UInt32(bitPattern: z))
        let seed = UInt32(truncatingIfNeeded: (unsignedX &* 0x1f1f1f1f) ^ unsignedZ)
        var generator = MT19937(seed: seed)
        let random = generator.nextUInt32()

        // Keep the same reciprocal-multiply modulus test used by the Android
        // implementation rather than replacing it with random % 10.
        let product = UInt64(random) &* 0xcccccccd
        let high = UInt32(truncatingIfNeeded: product >> 32)
        let quotientTimesTen = UInt32(truncatingIfNeeded: UInt64(high >> 3) &* 10)
        return random == quotientTimesTen
    }
}

private struct MT19937 {
    private static let stateCount = 624
    private static let period = 397
    private var state = [UInt32](repeating: 0, count: stateCount)
    private var index = stateCount

    init(seed: UInt32) {
        state[0] = seed
        if Self.stateCount > 1 {
            for i in 1..<Self.stateCount {
                let previous = state[i - 1]
                state[i] = 1_812_433_253 &* (previous ^ (previous >> 30)) &+ UInt32(i)
            }
        }
    }

    mutating func nextUInt32() -> UInt32 {
        if index >= Self.stateCount { twist() }
        var value = state[index]
        index += 1
        value ^= value >> 11
        value ^= (value << 7) & 0x9d2c5680
        value ^= (value << 15) & 0xefc60000
        value ^= value >> 18
        return value
    }

    private mutating func twist() {
        for i in 0..<Self.stateCount {
            let next = (i + 1) % Self.stateCount
            let combined = (state[i] & 0x80000000) | (state[next] & 0x7fffffff)
            var value = state[(i + Self.period) % Self.stateCount] ^ (combined >> 1)
            if combined & 1 != 0 { value ^= 0x9908b0df }
            state[i] = value
        }
        index = 0
    }
}
