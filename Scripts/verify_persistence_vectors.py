#!/usr/bin/env python3
"""Inspect exported regression bytes without either editor's decoder.

Run the Swift/C# regression entry points with MCBE_AUDIT_VECTORS set to
separate JSON paths, then pass those paths to this script.
"""
import base64
import json
import struct
import sys


class Reader:
    def __init__(self, raw):
        self.raw, self.offset = raw, 0

    def take(self, count):
        assert 0 <= count <= len(self.raw) - self.offset, "truncated record"
        value = self.raw[self.offset:self.offset + count]
        self.offset += count
        return value

    def number(self, fmt):
        return struct.unpack("<" + fmt, self.take(struct.calcsize("<" + fmt)))[0]

    def string(self):
        return self.take(self.number("H")).decode("utf-8")

    def nbt(self, kind):
        if kind in (1, 2, 3, 4, 5, 6):
            return self.number({1: "b", 2: "h", 3: "i", 4: "q", 5: "f", 6: "d"}[kind])
        if kind == 8:
            return self.string()
        if kind == 10:
            result = {}
            while True:
                tag = self.number("B")
                if not tag:
                    return result
                name = self.string()
                assert name not in result, "duplicate NBT field"
                result[name] = (tag, self.nbt(tag))
        if kind == 9:
            tag, count = self.number("B"), self.number("i")
            assert count >= 0
            return [self.nbt(tag) for _ in range(count)]
        if kind in (7, 11, 12):
            count = self.number("i")
            assert count >= 0
            return [self.number({7: "b", 11: "i", 12: "q"}[kind]) for _ in range(count)]
        raise AssertionError(f"invalid NBT type {kind}")


def verify(vector):
    raw = base64.b64decode(vector["raw"], validate=True)
    r = Reader(raw)
    version = r.number("B")
    assert version == vector["version"]
    index = vector["x"] * 256 + vector["z"] * 16 + vector["y"]
    if version in (0, 2, 3, 4, 5, 6, 7):
        ids, data = r.take(4096), r.take(2048)
        assert ids[index] == 57 and sum(value != 0 for value in ids) == 1
        assert not any(data)
        assert len(r.take(len(raw) - r.offset)) == 4096
        return raw
    count = 1 if version == 1 else r.number("B")
    if version == 9:
        y_index = r.number("b")
        assert y_index in (12, 13)
    assert 1 <= count <= 255
    for layer in range(count):
        header = r.number("B")
        assert header & 1 == 0, "runtime palette written to disk"
        bits = header >> 1
        assert bits in (0, 1, 2, 3, 4, 5, 6, 8, 16)
        if version in (1, 8):
            assert bits > 0, "old v1/v8 readers cannot read BPB=0"
        indices = [0] * 4096
        if bits:
            slots = 32 // bits
            for word_start in range(0, 4096, slots):
                word = r.number("I")
                for slot in range(min(slots, 4096 - word_start)):
                    indices[word_start + slot] = (word >> (slot * bits)) & ((1 << bits) - 1)
            palette_count = r.number("i")
        else:
            palette_count = 1
        assert 0 < palette_count <= (1 << bits)
        palette = []
        for _ in range(palette_count):
            assert r.number("B") == 10
            assert r.string() == ""
            state = r.nbt(10)
            assert state["name"][0] == 8
            if vector["val"]:
                assert state["val"] == (2, 0)
                assert "states" not in state and "version" not in state
            else:
                assert state["states"][0] == 10
                assert state["version"] == (3, 17825808)
                assert "val" not in state
            palette.append(state["name"][1])
        assert max(indices) < palette_count
        names = [palette[value] for value in indices]
        target_layer = vector.get("layer", 0)
        assert names[index] == (vector["block"] if layer == target_layer else "minecraft:air")
        assert sum(name != "minecraft:air" for name in names) == (1 if layer == target_layer else 0)
    assert r.offset == len(raw), "unexpected trailing bytes"
    return raw


def main(paths):
    assert paths, "pass one or more exported vector JSON files"
    first, total, compared = {}, 0, 0
    for path in paths:
        for vector in json.load(open(path, encoding="utf-8")):
            raw = verify(vector)
            total += 1
            name = vector["name"].lower()
            if name in first:
                assert first[name] == raw, f"Swift/C# byte mismatch: {name}"
                compared += 1
            first[name] = raw
    print(f"Independent disk-format checks passed: {total} vectors; {compared} byte-identical Swift/C# cases.")


if __name__ == "__main__":
    main(sys.argv[1:])
