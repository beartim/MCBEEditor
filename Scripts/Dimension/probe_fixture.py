"""Read-only probe of the attached SST-only Bedrock fixture; never opens LevelDB."""
import argparse
import ctypes
import json
import struct
import zlib
from pathlib import Path


def crc32c(data):
    crc = 0xffffffff
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82f63b78 if crc & 1 else 0)
    return crc ^ 0xffffffff


def check_crc(data, stored):
    actual = crc32c(data)
    masked = (((actual >> 15) | (actual << 17)) + 0xa282ead8) & 0xffffffff
    if masked != stored:
        raise ValueError('CRC32C mismatch')


def varint(data, pos=0):
    value = shift = 0
    while pos < len(data):
        byte = data[pos]
        pos += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, pos
        shift += 7
        if shift > 63:
            raise ValueError('oversized varint')
    raise ValueError('truncated varint')


def manifest_tables(db):
    current = (db / 'CURRENT').read_text().strip()
    data = (db / current).read_bytes()
    live, logical, edits = {}, bytearray(), 0
    pos = 0
    while pos < len(data):
        block_remaining = 32768 - pos % 32768
        if block_remaining < 7:
            pos += block_remaining
            continue
        if pos + 7 > len(data): raise ValueError('truncated manifest header')
        checksum, length, kind = struct.unpack_from('<IHB', data, pos)
        pos += 7
        fragment = data[pos:pos + length]
        if len(fragment) != length: raise ValueError('truncated manifest record')
        pos += length
        if kind != 0: check_crc(bytes([kind]) + fragment, checksum)
        if kind in (1, 2): logical = bytearray(fragment)
        elif kind in (3, 4): logical.extend(fragment)
        elif kind == 0 and length == 0: continue
        else: raise ValueError('unknown manifest record')
        if kind not in (1, 4): continue
        edits += 1
        p = 0
        while p < len(logical):
            tag, p = varint(logical, p)
            if tag in (2, 3, 4, 9):
                _, p = varint(logical, p)
            elif tag == 1:
                n, p = varint(logical, p)
                p += n
            elif tag == 5:
                _, p = varint(logical, p)
                n, p = varint(logical, p)
                p += n
            elif tag == 6:
                level, p = varint(logical, p)
                number, p = varint(logical, p)
                live.pop((level, number), None)
            elif tag == 7:
                level, p = varint(logical, p)
                number, p = varint(logical, p)
                size, p = varint(logical, p)
                for _ in range(2):
                    n, p = varint(logical, p)
                    p += n
                live[(level, number)] = size
            else:
                raise ValueError(f'unknown version edit tag {tag}')
    return current, edits, [f'{number:06d}.ldb' for _,number in sorted(live)]


def handle(data):
    offset, pos = varint(data)
    size, _ = varint(data, pos)
    return offset, size


def read_block(data, location):
    offset, size = location
    payload = data[offset:offset + size]
    compression = data[offset + size]
    check_crc(payload + bytes([compression]), struct.unpack_from('<I', data, offset + size + 1)[0])
    if compression == 0:
        return payload
    if compression in (2, 4):
        return zlib.decompress(payload, -15 if compression == 4 else 15)
    if compression == 1:
        lib = ctypes.CDLL('libsnappy.so.1')
        lib.snappy_uncompressed_length.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
        lib.snappy_uncompress.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t)]
        length = ctypes.c_size_t()
        if lib.snappy_uncompressed_length(payload, len(payload), ctypes.byref(length)):
            raise ValueError('invalid snappy block')
        result = ctypes.create_string_buffer(length.value)
        if lib.snappy_uncompress(payload, len(payload), result, ctypes.byref(length)):
            raise ValueError('snappy decompression failed')
        return result.raw[:length.value]
    raise ValueError(f'unsupported compression: {compression}')


def entries(block):
    restarts = struct.unpack_from('<I', block, len(block) - 4)[0]
    stop = len(block) - 4 * (restarts + 1)
    pos, previous = 0, b''
    while pos < stop:
        shared, pos = varint(block, pos)
        length, pos = varint(block, pos)
        value_length, pos = varint(block, pos)
        if shared > len(previous) or pos + length + value_length > stop:
            raise ValueError('malformed restart block')
        key = previous[:shared] + block[pos:pos + length]
        pos += length
        value = block[pos:pos + value_length]
        pos += value_length
        previous = key
        yield key, value
    if pos != stop:
        raise ValueError('block boundary mismatch')


def sst_entries(path):
    data = path.read_bytes()
    if struct.unpack_from('<Q', data, len(data) - 8)[0] != 0xdb4775248b80fb57:
        raise ValueError('not an SST table')
    footer = data[-48:-8]
    _, pos = varint(footer)
    _, pos = varint(footer, pos)
    index = read_block(data, handle(footer[pos:]))
    for _, location in entries(index):
        yield from entries(read_block(data, handle(location)))


class NbtReader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def number(self, fmt):
        value = struct.unpack_from('<' + fmt, self.data, self.pos)[0]
        self.pos += struct.calcsize(fmt)
        return value

    def string(self):
        size = self.number('H')
        value = self.data[self.pos:self.pos + size].decode('utf-8')
        self.pos += size
        return value

    def value(self, kind):
        if kind in range(1, 7):
            return self.number({1:'b', 2:'h', 3:'i', 4:'q', 5:'f', 6:'d'}[kind])
        if kind == 7:
            length = self.number('i')
            if length < 0: raise ValueError('negative array')
            value = self.data[self.pos:self.pos + length]
            self.pos += length
            return {'byte_array_hex': value.hex()}
        if kind == 8:
            return self.string()
        if kind == 9:
            element, length = self.number('B'), self.number('i')
            if length < 0: raise ValueError('negative list')
            return [self.value(element) for _ in range(length)]
        if kind == 10:
            result = {}
            while True:
                tag = self.number('B')
                if tag == 0: break
                name = self.string()
                result[name] = self.value(tag)
            return result
        if kind in (11, 12):
            length = self.number('i')
            if length < 0: raise ValueError('negative array')
            return [self.number('i' if kind == 11 else 'q') for _ in range(length)]
        raise ValueError(f'unsupported NBT type {kind}')

    def document(self):
        kind = self.number('B')
        name = self.string()
        value = self.value(kind)
        return name, value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('world', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    latest, count, table_names = {}, 0, []
    manifest, edits, live_tables = manifest_tables(args.world / 'db')
    if list((args.world / 'db').glob('*.log')):
        raise ValueError('This read-only fixture probe does not replay WAL files')
    for path in [args.world / 'db' / name for name in live_tables]:
        table_names.append(path.name)
        for internal, value in sst_entries(path):
            count += 1
            if len(internal) < 8: raise ValueError('short internal key')
            key, trailer = internal[:-8], struct.unpack('<Q', internal[-8:])[0]
            sequence, kind = trailer >> 8, trailer & 255
            if key not in latest or sequence > latest[key][0]:
                latest[key] = (sequence, kind, value)
    records = {key: entry[2] for key, entry in latest.items() if entry[1] == 1}
    chunks, named, digests, actors = {}, {}, {}, []
    tags = set(range(0x2b, 0x42)) | {0x76}
    for key, value in records.items():
        if key.startswith(b'digp') and len(key) in (12, 16):
            dim = struct.unpack_from('<i', key, 12)[0] if len(key) == 16 else 0
            if len(value) % 8: raise ValueError('misaligned actor digest')
            digests.setdefault(str(dim), []).append({'key_hex':key.hex(), 'actor_references':[value[i:i+8].hex() for i in range(0,len(value),8)]})
        if key.startswith(b'actorprefix'):
            actors.append({'reference_hex':key[len(b'actorprefix'):].hex(), 'size':len(value)})
        if len(key) in (9, 10) and key[8] in tags:
            x, z = struct.unpack_from('<ii', key)
            dimension = 0
        elif len(key) in (13, 14) and key[12] in tags:
            x, z, dimension = struct.unpack_from('<iii', key)
        else:
            try:
                name = key.decode('utf-8')
                if not name.isprintable(): continue
            except UnicodeError:
                continue
            entry = {'size':len(value)}
            try:
                reader = NbtReader(value)
                root_name, root = reader.document()
                entry.update(nbt=root, root_name=root_name, bytes_consumed=reader.pos)
            except (ValueError, UnicodeError, struct.error, IndexError):
                entry['hex_prefix'] = value[:160].hex()
            named[name] = entry
            continue
        chunks.setdefault(dimension, {'positions':set(), 'records':0})
        chunks[dimension]['positions'].add((x, z))
        chunks[dimension]['records'] += 1
    level = (args.world / 'level.dat').read_bytes()
    version, length = struct.unpack_from('<II', level)
    reader = NbtReader(level[8:])
    _, root = reader.document()
    report = {
        'manifest':manifest, 'manifest_edits':edits,
        'tables':table_names, 'internal_records':count, 'live_user_keys':len(records),
        'actor_digests':digests, 'actor_records':actors,
        'chunk_dimensions':{str(d):{'chunks':len(v['positions']), 'records':v['records'],
            'positions':sorted(v['positions'])} for d,v in sorted(chunks.items())},
        'named_database_records':named, 'level_dat_version':version,
        'level_dat_declared_length':length, 'level_dat_consumed_length':reader.pos,
        'level_dat':root,
    }
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k:report[k] for k in ['manifest','manifest_edits','tables','internal_records','live_user_keys']}, ensure_ascii=False))
    print('Chunk counts:', {d:{k:v for k,v in counts.items() if k != 'positions'} for d,counts in report['chunk_dimensions'].items()})
    print('Named keys:', ', '.join(named))
    for name,entry in named.items():
        if 'dimension' in name.lower(): print(name, json.dumps(entry, ensure_ascii=False))


if __name__ == '__main__':
    main()
