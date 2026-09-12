namespace MCBEEditor.Core.Chunk;

/// <summary>
/// Bedrock Edition slime-chunk coordinate algorithm. The world seed is not used;
/// signed chunk X/Z are mixed into the MT19937 seed exactly like the iOS/Android renderer.
/// </summary>
public static class BedrockSlimeChunk
{
    public static bool IsSlimeChunk(int x, int z)
    {
        var unsignedX = (ulong)(uint)x;
        var unsignedZ = (ulong)(uint)z;
        var seed = unchecked((uint)((unsignedX * 0x1f1f1f1fUL) ^ unsignedZ));
        var generator = new Mt19937(seed);
        var random = generator.NextUInt32();
        var product = (ulong)random * 0xcccccccdUL;
        var high = unchecked((uint)(product >> 32));
        var quotientTimesTen = unchecked((uint)((ulong)(high >> 3) * 10UL));
        return random == quotientTimesTen;
    }

    private sealed class Mt19937
    {
        private const int StateCount = 624;
        private const int Period = 397;
        private readonly uint[] _state = new uint[StateCount];
        private int _index = StateCount;

        public Mt19937(uint seed)
        {
            _state[0] = seed;
            for (var i = 1; i < StateCount; i++)
            {
                var previous = _state[i - 1];
                _state[i] = unchecked(1_812_433_253u * (previous ^ (previous >> 30)) + (uint)i);
            }
        }

        public uint NextUInt32()
        {
            if (_index >= StateCount) Twist();
            var value = _state[_index++];
            value ^= value >> 11;
            value ^= (value << 7) & 0x9d2c5680u;
            value ^= (value << 15) & 0xefc60000u;
            value ^= value >> 18;
            return value;
        }

        private void Twist()
        {
            for (var i = 0; i < StateCount; i++)
            {
                var next = (i + 1) % StateCount;
                var combined = (_state[i] & 0x80000000u) | (_state[next] & 0x7fffffffu);
                var value = _state[(i + Period) % StateCount] ^ (combined >> 1);
                if ((combined & 1u) != 0) value ^= 0x9908b0dfu;
                _state[i] = value;
            }
            _index = 0;
        }
    }
}
