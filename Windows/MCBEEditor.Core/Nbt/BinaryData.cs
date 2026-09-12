using System.Buffers.Binary;

namespace MCBEEditor.Core.Nbt;

internal ref struct BinaryDataReader
{
    private readonly ReadOnlySpan<byte> _data;
    private int _offset;

    public BinaryDataReader(ReadOnlySpan<byte> data)
    {
        _data = data;
        _offset = 0;
    }

    public int Offset => _offset;
    public int Remaining => _data.Length - _offset;
    public bool IsAtEnd => _offset >= _data.Length;
    public ReadOnlySpan<byte> RemainingSpan => _data[_offset..];

    public void Skip(int count)
    {
        Ensure(count);
        _offset += count;
    }

    public byte ReadByte()
    {
        Ensure(1);
        return _data[_offset++];
    }

    public byte[] ReadBytes(int count)
    {
        if (count < 0)
            throw new InvalidDataException($"读取 {count} 字节越界");
        Ensure(count);
        var result = _data.Slice(_offset, count).ToArray();
        _offset += count;
        return result;
    }

    public ushort ReadUInt16LE()
    {
        Ensure(2);
        var value = BinaryPrimitives.ReadUInt16LittleEndian(_data.Slice(_offset, 2));
        _offset += 2;
        return value;
    }

    public short ReadInt16LE()
    {
        Ensure(2);
        var value = BinaryPrimitives.ReadInt16LittleEndian(_data.Slice(_offset, 2));
        _offset += 2;
        return value;
    }

    public ushort ReadUInt16BE()
    {
        Ensure(2);
        var value = BinaryPrimitives.ReadUInt16BigEndian(_data.Slice(_offset, 2));
        _offset += 2;
        return value;
    }

    public short ReadInt16BE()
    {
        Ensure(2);
        var value = BinaryPrimitives.ReadInt16BigEndian(_data.Slice(_offset, 2));
        _offset += 2;
        return value;
    }

    public uint ReadUInt32LE()
    {
        Ensure(4);
        var value = BinaryPrimitives.ReadUInt32LittleEndian(_data.Slice(_offset, 4));
        _offset += 4;
        return value;
    }

    public int ReadInt32LE()
    {
        Ensure(4);
        var value = BinaryPrimitives.ReadInt32LittleEndian(_data.Slice(_offset, 4));
        _offset += 4;
        return value;
    }

    public int ReadInt32BE()
    {
        Ensure(4);
        var value = BinaryPrimitives.ReadInt32BigEndian(_data.Slice(_offset, 4));
        _offset += 4;
        return value;
    }

    public long ReadInt64LE()
    {
        Ensure(8);
        var value = BinaryPrimitives.ReadInt64LittleEndian(_data.Slice(_offset, 8));
        _offset += 8;
        return value;
    }

    public long ReadInt64BE()
    {
        Ensure(8);
        var value = BinaryPrimitives.ReadInt64BigEndian(_data.Slice(_offset, 8));
        _offset += 8;
        return value;
    }

    public float ReadFloatLE() => BitConverter.Int32BitsToSingle(ReadInt32LE());
    public float ReadFloatBE() => BitConverter.Int32BitsToSingle(ReadInt32BE());
    public double ReadDoubleLE() => BitConverter.Int64BitsToDouble(ReadInt64LE());
    public double ReadDoubleBE() => BitConverter.Int64BitsToDouble(ReadInt64BE());

    public ulong ReadUnsignedVarInt(int maxBytes = 5)
    {
        if (maxBytes is < 1 or > 10)
            throw new InvalidDataException("VarInt 字节上限无效");

        ulong result = 0;
        for (var index = 0; index < maxBytes; index++)
        {
            var value = ReadByte();
            var payload = (ulong)(value & 0x7F);
            if ((maxBytes == 5 && index == 4 && payload > 0x0F) || (index == 9 && payload > 1))
                throw new InvalidDataException("VarInt 数值溢出");

            result |= payload << (index * 7);
            if ((value & 0x80) == 0)
                return result;
        }

        throw new InvalidDataException("VarInt 过长");
    }

    public int ReadSignedVarInt32()
    {
        var raw = checked((uint)ReadUnsignedVarInt(5));
        return unchecked((int)((raw >> 1) ^ (uint)-(int)(raw & 1)));
    }

    public long ReadSignedVarInt64()
    {
        var raw = ReadUnsignedVarInt(10);
        return unchecked((long)((raw >> 1) ^ (ulong)-(long)(raw & 1)));
    }

    private void Ensure(int count)
    {
        if (count < 0 || count > Remaining)
            throw new InvalidDataException($"读取 {count} 字节越界");
    }
}

internal sealed class BinaryDataWriter
{
    private readonly MemoryStream _stream = new();

    public byte[] ToArray() => _stream.ToArray();

    public void WriteByte(byte value) => _stream.WriteByte(value);
    public void WriteBytes(ReadOnlySpan<byte> value) => _stream.Write(value);

    public void WriteUInt16LE(ushort value)
    {
        Span<byte> buffer = stackalloc byte[2];
        BinaryPrimitives.WriteUInt16LittleEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteInt16LE(short value)
    {
        Span<byte> buffer = stackalloc byte[2];
        BinaryPrimitives.WriteInt16LittleEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteUInt16BE(ushort value)
    {
        Span<byte> buffer = stackalloc byte[2];
        BinaryPrimitives.WriteUInt16BigEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteInt16BE(short value)
    {
        Span<byte> buffer = stackalloc byte[2];
        BinaryPrimitives.WriteInt16BigEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteUInt32LE(uint value)
    {
        Span<byte> buffer = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteInt32LE(int value)
    {
        Span<byte> buffer = stackalloc byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteInt32BE(int value)
    {
        Span<byte> buffer = stackalloc byte[4];
        BinaryPrimitives.WriteInt32BigEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteInt64LE(long value)
    {
        Span<byte> buffer = stackalloc byte[8];
        BinaryPrimitives.WriteInt64LittleEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteInt64BE(long value)
    {
        Span<byte> buffer = stackalloc byte[8];
        BinaryPrimitives.WriteInt64BigEndian(buffer, value);
        _stream.Write(buffer);
    }

    public void WriteFloatLE(float value) => WriteInt32LE(BitConverter.SingleToInt32Bits(value));
    public void WriteFloatBE(float value) => WriteInt32BE(BitConverter.SingleToInt32Bits(value));
    public void WriteDoubleLE(double value) => WriteInt64LE(BitConverter.DoubleToInt64Bits(value));
    public void WriteDoubleBE(double value) => WriteInt64BE(BitConverter.DoubleToInt64Bits(value));

    public void WriteUnsignedVarInt(ulong value)
    {
        do
        {
            var current = (byte)(value & 0x7F);
            value >>= 7;
            if (value != 0)
                current |= 0x80;
            WriteByte(current);
        } while (value != 0);
    }

    public void WriteSignedVarInt(int value)
    {
        var zigzag = unchecked((uint)((value << 1) ^ (value >> 31)));
        WriteUnsignedVarInt(zigzag);
    }

    public void WriteSignedVarLong(long value)
    {
        var zigzag = unchecked((ulong)((value << 1) ^ (value >> 63)));
        WriteUnsignedVarInt(zigzag);
    }
}
