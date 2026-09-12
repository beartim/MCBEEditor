namespace MCBEEditor.Core.Nbt;

public static class BedrockNbtCodec
{
    public static NbtDocument Decode(ReadOnlySpan<byte> data, NbtEncoding encoding = NbtEncoding.LittleEndian, int maximumDepth = 256)
        => DecodeOne(data, out _, encoding, maximumDepth);

    /// <summary>
    /// Decodes one NBT document from the start of <paramref name="data"/> and
    /// reports exactly how many bytes were consumed. Bedrock SubChunk palettes
    /// store consecutive unnamed NBT compounds, so callers must be able to
    /// continue at the byte immediately following one document.
    /// </summary>
    public static NbtDocument DecodeOne(
        ReadOnlySpan<byte> data,
        out int bytesRead,
        NbtEncoding encoding = NbtEncoding.LittleEndian,
        int maximumDepth = 256)
    {
        var reader = new BinaryDataReader(data);
        var rawType = reader.ReadByte();
        if (!Enum.IsDefined(typeof(NbtTagType), rawType) || rawType == (byte)NbtTagType.End)
            throw new InvalidDataException($"NBT 根标签类型无效：{rawType}");

        var type = (NbtTagType)rawType;
        var name = ReadString(ref reader, encoding);
        var value = ReadPayload(type, ref reader, encoding, 0, maximumDepth);
        bytesRead = reader.Offset;
        return new NbtDocument(name, value);
    }

    public static byte[] Encode(NbtDocument document, NbtEncoding encoding = NbtEncoding.LittleEndian)
    {
        var writer = new BinaryDataWriter();
        writer.WriteByte((byte)document.Root.Type);
        WriteString(document.RootName, writer, encoding);
        WritePayload(document.Root, writer, encoding);
        return writer.ToArray();
    }

    private static NbtValue ReadPayload(NbtTagType type, ref BinaryDataReader reader, NbtEncoding encoding, int depth, int maximumDepth)
    {
        if (depth > maximumDepth)
            throw new InvalidDataException($"NBT 嵌套超过 {maximumDepth} 层");

        return type switch
        {
            NbtTagType.End => throw new InvalidDataException("End 标签不能作为值"),
            NbtTagType.Byte => new NbtByteValue(unchecked((sbyte)reader.ReadByte())),
            NbtTagType.Short => new NbtShortValue(encoding == NbtEncoding.BigEndian ? reader.ReadInt16BE() : reader.ReadInt16LE()),
            NbtTagType.Int => new NbtIntValue(ReadInt(ref reader, encoding)),
            NbtTagType.Long => new NbtLongValue(ReadLong(ref reader, encoding)),
            NbtTagType.Float => new NbtFloatValue(encoding == NbtEncoding.BigEndian ? reader.ReadFloatBE() : reader.ReadFloatLE()),
            NbtTagType.Double => new NbtDoubleValue(encoding == NbtEncoding.BigEndian ? reader.ReadDoubleBE() : reader.ReadDoubleLE()),
            NbtTagType.ByteArray => new NbtByteArrayValue(reader.ReadBytes(ReadLength(ref reader, encoding))),
            NbtTagType.String => new NbtStringValue(ReadString(ref reader, encoding)),
            NbtTagType.List => ReadList(ref reader, encoding, depth, maximumDepth),
            NbtTagType.Compound => ReadCompound(ref reader, encoding, depth, maximumDepth),
            NbtTagType.IntArray => ReadIntArray(ref reader, encoding),
            NbtTagType.LongArray => ReadLongArray(ref reader, encoding),
            _ => throw new InvalidDataException($"不支持的 NBT 类型：{type}")
        };
    }

    private static NbtListValue ReadList(ref BinaryDataReader reader, NbtEncoding encoding, int depth, int maximumDepth)
    {
        var rawElementType = reader.ReadByte();
        if (!Enum.IsDefined(typeof(NbtTagType), rawElementType))
            throw new InvalidDataException($"NBT List 元素类型无效：{rawElementType}");

        var elementType = (NbtTagType)rawElementType;
        var count = ReadLength(ref reader, encoding);
        if (elementType == NbtTagType.End && count != 0)
            throw new InvalidDataException("NBT List 的 End 元素类型只允许用于空列表");

        var values = new NbtValue[count];
        for (var index = 0; index < count; index++)
            values[index] = ReadPayload(elementType, ref reader, encoding, depth + 1, maximumDepth);
        return new NbtListValue(elementType, values);
    }

    private static NbtCompoundValue ReadCompound(ref BinaryDataReader reader, NbtEncoding encoding, int depth, int maximumDepth)
    {
        var tags = new List<NbtNamedTag>();
        while (true)
        {
            var rawType = reader.ReadByte();
            if (rawType == (byte)NbtTagType.End)
                break;
            if (!Enum.IsDefined(typeof(NbtTagType), rawType))
                throw new InvalidDataException($"NBT Compound 子标签类型无效：{rawType}");

            var childType = (NbtTagType)rawType;
            var name = ReadString(ref reader, encoding);
            var value = ReadPayload(childType, ref reader, encoding, depth + 1, maximumDepth);
            tags.Add(new NbtNamedTag(name, value));
        }
        return new NbtCompoundValue(tags);
    }

    private static NbtIntArrayValue ReadIntArray(ref BinaryDataReader reader, NbtEncoding encoding)
    {
        var count = ReadLength(ref reader, encoding);
        var values = new int[count];
        for (var i = 0; i < count; i++)
            values[i] = ReadInt(ref reader, encoding);
        return new NbtIntArrayValue(values);
    }

    private static NbtLongArrayValue ReadLongArray(ref BinaryDataReader reader, NbtEncoding encoding)
    {
        var count = ReadLength(ref reader, encoding);
        var values = new long[count];
        for (var i = 0; i < count; i++)
            values[i] = ReadLong(ref reader, encoding);
        return new NbtLongArrayValue(values);
    }

    private static int ReadInt(ref BinaryDataReader reader, NbtEncoding encoding) => encoding switch
    {
        NbtEncoding.BigEndian => reader.ReadInt32BE(),
        NbtEncoding.LittleEndian => reader.ReadInt32LE(),
        NbtEncoding.LittleEndianVarInt => reader.ReadSignedVarInt32(),
        _ => throw new ArgumentOutOfRangeException(nameof(encoding))
    };

    private static long ReadLong(ref BinaryDataReader reader, NbtEncoding encoding) => encoding switch
    {
        NbtEncoding.BigEndian => reader.ReadInt64BE(),
        NbtEncoding.LittleEndian => reader.ReadInt64LE(),
        NbtEncoding.LittleEndianVarInt => reader.ReadSignedVarInt64(),
        _ => throw new ArgumentOutOfRangeException(nameof(encoding))
    };

    private static int ReadLength(ref BinaryDataReader reader, NbtEncoding encoding)
    {
        long raw = encoding switch
        {
            NbtEncoding.BigEndian => reader.ReadInt32BE(),
            NbtEncoding.LittleEndian => reader.ReadInt32LE(),
            NbtEncoding.LittleEndianVarInt => reader.ReadSignedVarInt32(),
            _ => throw new ArgumentOutOfRangeException(nameof(encoding))
        };

        if (raw < 0 || raw > 100_000_000 || raw > int.MaxValue)
            throw new InvalidDataException($"NBT 长度无效：{raw}");
        return (int)raw;
    }

    private static string ReadString(ref BinaryDataReader reader, NbtEncoding encoding)
    {
        int length = encoding switch
        {
            NbtEncoding.BigEndian => reader.ReadUInt16BE(),
            NbtEncoding.LittleEndian => reader.ReadUInt16LE(),
            NbtEncoding.LittleEndianVarInt => ReadVarStringLength(ref reader),
            _ => throw new ArgumentOutOfRangeException(nameof(encoding))
        };

        return NbtRawStringCodec.Decode(reader.ReadBytes(length));
    }

    private static int ReadVarStringLength(ref BinaryDataReader reader)
    {
        var value = reader.ReadUnsignedVarInt(5);
        if (value > 16_777_216 || value > int.MaxValue)
            throw new InvalidDataException("NBT 字符串过长");
        return (int)value;
    }

    private static void WritePayload(NbtValue value, BinaryDataWriter writer, NbtEncoding encoding)
    {
        switch (value)
        {
            case NbtByteValue item:
                writer.WriteByte(unchecked((byte)item.Value));
                break;
            case NbtShortValue item:
                if (encoding == NbtEncoding.BigEndian) writer.WriteInt16BE(item.Value); else writer.WriteInt16LE(item.Value);
                break;
            case NbtIntValue item:
                WriteInt(item.Value, writer, encoding);
                break;
            case NbtLongValue item:
                WriteLong(item.Value, writer, encoding);
                break;
            case NbtFloatValue item:
                if (encoding == NbtEncoding.BigEndian) writer.WriteFloatBE(item.Value); else writer.WriteFloatLE(item.Value);
                break;
            case NbtDoubleValue item:
                if (encoding == NbtEncoding.BigEndian) writer.WriteDoubleBE(item.Value); else writer.WriteDoubleLE(item.Value);
                break;
            case NbtByteArrayValue item:
                WriteLength(item.Value.Length, writer, encoding);
                writer.WriteBytes(item.Value);
                break;
            case NbtStringValue item:
                WriteString(item.Value, writer, encoding);
                break;
            case NbtListValue item:
                writer.WriteByte((byte)item.ElementType);
                WriteLength(item.Values.Count, writer, encoding);
                foreach (var child in item.Values)
                {
                    if (child.Type != item.ElementType)
                        throw new InvalidDataException($"NBT List 声明类型 {item.ElementType}，但实际包含 {child.Type}");
                    WritePayload(child, writer, encoding);
                }
                break;
            case NbtCompoundValue item:
                foreach (var tag in item.Tags)
                {
                    writer.WriteByte((byte)tag.Value.Type);
                    WriteString(tag.Name, writer, encoding);
                    WritePayload(tag.Value, writer, encoding);
                }
                writer.WriteByte((byte)NbtTagType.End);
                break;
            case NbtIntArrayValue item:
                WriteLength(item.Values.Count, writer, encoding);
                foreach (var number in item.Values) WriteInt(number, writer, encoding);
                break;
            case NbtLongArrayValue item:
                WriteLength(item.Values.Count, writer, encoding);
                foreach (var number in item.Values) WriteLong(number, writer, encoding);
                break;
            default:
                throw new InvalidDataException($"不支持写入的 NBT 类型：{value.GetType().Name}");
        }
    }

    private static void WriteInt(int value, BinaryDataWriter writer, NbtEncoding encoding)
    {
        switch (encoding)
        {
            case NbtEncoding.BigEndian: writer.WriteInt32BE(value); break;
            case NbtEncoding.LittleEndian: writer.WriteInt32LE(value); break;
            case NbtEncoding.LittleEndianVarInt: writer.WriteSignedVarInt(value); break;
            default: throw new ArgumentOutOfRangeException(nameof(encoding));
        }
    }

    private static void WriteLong(long value, BinaryDataWriter writer, NbtEncoding encoding)
    {
        switch (encoding)
        {
            case NbtEncoding.BigEndian: writer.WriteInt64BE(value); break;
            case NbtEncoding.LittleEndian: writer.WriteInt64LE(value); break;
            case NbtEncoding.LittleEndianVarInt: writer.WriteSignedVarLong(value); break;
            default: throw new ArgumentOutOfRangeException(nameof(encoding));
        }
    }

    private static void WriteLength(int count, BinaryDataWriter writer, NbtEncoding encoding)
    {
        if (count < 0)
            throw new InvalidDataException($"NBT 长度无法编码：{count}");
        WriteInt(count, writer, encoding);
    }

    private static void WriteString(string value, BinaryDataWriter writer, NbtEncoding encoding)
    {
        var bytes = NbtRawStringCodec.Encode(value);
        switch (encoding)
        {
            case NbtEncoding.BigEndian:
                if (bytes.Length > ushort.MaxValue) throw new InvalidDataException("NBT 字符串超过 65535 字节");
                writer.WriteUInt16BE((ushort)bytes.Length);
                break;
            case NbtEncoding.LittleEndian:
                if (bytes.Length > ushort.MaxValue) throw new InvalidDataException("NBT 字符串超过 65535 字节");
                writer.WriteUInt16LE((ushort)bytes.Length);
                break;
            case NbtEncoding.LittleEndianVarInt:
                writer.WriteUnsignedVarInt((ulong)bytes.Length);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(encoding));
        }
        writer.WriteBytes(bytes);
    }
}
