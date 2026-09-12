using System.Runtime.InteropServices;

namespace MCBEEditor.Core.LevelDB;

internal static class NativeLevelDbMethods
{
    internal const string LibraryName = "MCBEEditor.LevelDB.Native";

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_db_open")]
    internal static extern int Open(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path,
        int readOnly,
        out IntPtr database,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_db_close")]
    internal static extern void Close(IntPtr database);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_db_get")]
    internal static extern int Get(
        IntPtr database,
        byte[] key,
        nuint keyLength,
        out IntPtr value,
        out nuint valueLength,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_db_put")]
    internal static extern int Put(
        IntPtr database,
        byte[] key,
        nuint keyLength,
        byte[] value,
        nuint valueLength,
        int sync,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_db_delete")]
    internal static extern int Delete(
        IntPtr database,
        byte[] key,
        nuint keyLength,
        int sync,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_batch_create")]
    internal static extern IntPtr BatchCreate();

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_batch_destroy")]
    internal static extern void BatchDestroy(IntPtr batch);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_batch_put")]
    internal static extern int BatchPut(
        IntPtr batch,
        byte[] key,
        nuint keyLength,
        byte[] value,
        nuint valueLength,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_batch_delete")]
    internal static extern int BatchDelete(
        IntPtr batch,
        byte[] key,
        nuint keyLength,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_db_write_batch")]
    internal static extern int WriteBatch(
        IntPtr database,
        IntPtr batch,
        int sync,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_iter_create")]
    internal static extern IntPtr IteratorCreate(
        IntPtr database,
        byte[]? prefix,
        nuint prefixLength,
        int includeValues,
        out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_iter_destroy")]
    internal static extern void IteratorDestroy(IntPtr iterator);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_iter_valid")]
    internal static extern int IteratorValid(IntPtr iterator);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_iter_next")]
    internal static extern void IteratorNext(IntPtr iterator);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_iter_key")]
    internal static extern IntPtr IteratorKey(IntPtr iterator, out nuint length);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_iter_value")]
    internal static extern IntPtr IteratorValue(IntPtr iterator, out nuint length);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_iter_status")]
    internal static extern int IteratorStatus(IntPtr iterator, out IntPtr error);

    [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "mcbe_free")]
    internal static extern void Free(IntPtr pointer);
}
