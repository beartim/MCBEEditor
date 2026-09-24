#!/usr/bin/env python3
"""Independent NBT fixtures against a real CLI. Usage: python3 ... -- /path/to/mcbe-cli"""
from __future__ import annotations
import argparse
import gzip
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

TYPES = {name: index for index, name in enumerate(("end", "byte", "short", "int", "long", "float", "double", "byteArray", "string", "list", "compound", "intArray", "longArray"))}


def tag(kind, value):
    return {"type": kind, "value": value}


def fixture():
    return {"name": "中文根", **tag("compound", {
        "byte": tag("byte", -128), "short": tag("short", -32768), "int": tag("int", -2147483648),
        "odd": tag("long", 9007199254740993), "max": tag("long", 9223372036854775807),
        "min": tag("long", -9223372036854775808), "float": tag("float", 1.5), "double": tag("double", -2.25),
        "text": tag("string", "中文与空值结构"), "bytes": tag("byteArray", [-128, -1, 0, 127]),
        "ints": tag("intArray", [-2147483648, 0, 2147483647]),
        "longs": tag("longArray", [-9223372036854775808, 9007199254740993, 9223372036854775807]),
        "emptyCompound": tag("compound", {}), "emptyList": tag("list", {"type": "end", "value": []}),
        "nestedList": tag("list", {"type": "list", "value": [tag("list", {"type": "int", "value": [tag("int", 7)]})]}),
    })}


def encode(document, encoding):
    endian = ">" if encoding == "big-endian" else "<"
    varint = encoding == "little-varint"
    def unsigned(value):
        result = bytearray()
        while value >= 128:
            result.append((value & 127) | 128)
            value >>= 7
        result.append(value)
        return bytes(result)
    def signed(value, bits):
        return unsigned((value << 1) ^ (value >> (bits - 1)))
    def integer(value):
        return signed(value, 32) if varint else struct.pack(endian + "i", value)
    def string(value):
        raw = value.encode("utf-8")
        return (unsigned(len(raw)) if varint else struct.pack(endian + "H", len(raw))) + raw
    def payload(node):
        kind, value = node["type"], node["value"]
        if kind == "byte": return struct.pack("b", value)
        if kind == "short": return struct.pack(endian + "h", value)
        if kind == "int": return integer(value)
        if kind == "long": return signed(value, 64) if varint else struct.pack(endian + "q", value)
        if kind == "float": return struct.pack(endian + "f", value)
        if kind == "double": return struct.pack(endian + "d", value)
        if kind == "string": return string(value)
        if kind == "compound": return b"".join(bytes([TYPES[v["type"]]]) + string(k) + payload(v) for k, v in value.items()) + b"\0"
        if kind == "list": return bytes([TYPES[value["type"]]]) + integer(len(value["value"])) + b"".join(payload(v) for v in value["value"])
        element = {"byteArray": "byte", "intArray": "int", "longArray": "long"}[kind]
        return integer(len(value)) + b"".join(payload(tag(element, v)) for v in value)
    return bytes([TYPES[document["type"]]]) + string(document.get("name", "")) + payload(document)


def normalized(node):
    kind, value = node["type"], node["value"]
    if kind == "compound": value = {key: normalized(item) for key, item in value.items()}
    elif kind == "list": value = (value["type"], [normalized(item) for item in value["value"]])
    elif kind == "long": value = int(value)
    elif kind == "longArray": value = list(map(int, value))
    return kind, value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command: parser.error("supply a real CLI executable after --")
    calls = 0
    with tempfile.TemporaryDirectory(prefix="mcbe-conversion-") as temporary:
        root = Path(temporary)
        env = dict(os.environ, MCBEEDITOR_PORTABLE_ROOT=str(root / "portable"))
        def invoke(source, target, fmt, overwrite=False, expected=0):
            nonlocal calls
            args = ["--convert", str(source), "--to", fmt, "--output", str(target)]
            if overwrite: args.append("--overwrite")
            result = subprocess.run(command + args, capture_output=True, timeout=30, env=env)
            assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
            if expected: assert result.stderr and not result.stdout, "failure must not report success"
            else: assert not result.stderr, result.stderr
            assert not list(root.glob(".mcbe-convert-*.tmp")), "conversion temporary leaked"
            calls += 1
        document = fixture()
        def check_json(path, count):
            obj = json.loads(path.read_bytes())
            documents = obj.get("documents", [obj])
            assert len(documents) == count
            for doc in documents:
                assert doc["name"] == document["name"]
                assert normalized(doc.get("root", doc)) == normalized(document)
        # Python writes all binary fixtures; neither product encoder supplies the oracle.
        for encoding in ("big-endian", "little-endian", "little-varint"):
            binary = encode(document, encoding)
            for name, wrap in (("raw", lambda value: value), ("gzip", gzip.compress), ("zlib", zlib.compress)):
                source = root / f"{encoding}-{name}.nbt"
                source.write_bytes(wrap(binary + binary))
                output = source.with_suffix(".json")
                invoke(source, output, "json")
                check_json(output, 2)
                target = root / f"roundtrip-{encoding}-{name}.nbt"
                invoke(output, target, encoding)
                invoke(target, output, "json", overwrite=True)
                check_json(output, 2)
        source = root / "numeric.json"
        source.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
        target = root / "numeric.nbt"
        invoke(source, target, "little-endian")
        output = root / "numeric-out.json"
        invoke(target, output, "json")
        check_json(output, 1)
        before = target.read_bytes()
        invoke(target, target, "big-endian", expected=3)
        assert target.read_bytes() == before
        invoke(target, target, "big-endian", overwrite=True)
        invoke(target, output, "json", overwrite=True)
        check_json(output, 1)
        folder = root / "folder.json"
        folder.mkdir()
        invoke(target, folder, "json", overwrite=True, expected=3)
        bad = root / "bad.nbt"
        sentinel = b"existing output must survive"
        output.write_bytes(sentinel)
        binary = encode(document, "little-endian")
        corrupt_gzip = bytearray(gzip.compress(binary)); corrupt_gzip[-8] ^= 1
        for payload in (b"", b"\xff", binary[:-1], bytes(corrupt_gzip), gzip.compress(binary)[:12]):
            bad.write_bytes(payload)
            invoke(bad, output, "json", overwrite=True, expected=3)
            assert output.read_bytes() == sentinel
        # Duplicate compound names are valid to the binary reader, but cannot be
        # represented by the current JSON object schema: refuse before publishing.
        duplicate = b"\x0a\x00\x00" + b"\x03\x01\x00x\x01\x00\x00\x00" + b"\x03\x01\x00x\x02\x00\x00\x00\x00"
        bad.write_bytes(duplicate)
        invoke(bad, output, "json", overwrite=True, expected=3)
        assert output.read_bytes() == sentinel
        invalid = root / "invalid.json"
        before_invalid = target.read_bytes()
        for payload in ('{"type":"float","value":1e39}', '{"type":"double","value":"NaN"}', '{"type":"int","value":true}', 'null', '{"documents":[]}'):
            invalid.write_text(payload, encoding="utf-8")
            invoke(invalid, target, "little-endian", overwrite=True, expected=3)
            assert target.read_bytes() == before_invalid
        invalid.write_text("[]", encoding="utf-8")
        invoke(invalid, target, "little-endian", overwrite=True)
        assert target.read_bytes() == b"\x09\0\0\0\0\0\0\0", "empty array must remain one empty End list"
        bad.write_bytes(binary + binary)
        structure = root / "invalid.mcstructure"
        invoke(bad, structure, "mcstructure", expected=3)
        assert not structure.exists()
    print(f"PASS NBT conversion: {calls} real CLI invocations")


if __name__ == "__main__": main()
