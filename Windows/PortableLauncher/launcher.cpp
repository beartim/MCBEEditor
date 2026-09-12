#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>

namespace {
constexpr int kPayloadResourceId = 101;
constexpr wchar_t kMutexName[] = L"MCBEEditor.Portable.SingleInstance";

std::wstring Join(const std::wstring& left, const std::wstring& right) {
    if (left.empty()) return right;
    if (left.back() == L'\\' || left.back() == L'/') return left + right;
    return left + L"\\" + right;
}

std::wstring ModulePath() {
    std::vector<wchar_t> buffer(32768);
    DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size()) return {};
    return std::wstring(buffer.data(), length);
}

std::wstring ParentPath(const std::wstring& path) {
    auto slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"." : path.substr(0, slash);
}

bool EnsureDirectory(const std::wstring& path) {
    if (path.empty()) return false;
    DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) return (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    auto parent = ParentPath(path);
    if (parent != path && !parent.empty() && parent != L".") EnsureDirectory(parent);
    return CreateDirectoryW(path.c_str(), nullptr) != 0 || GetLastError() == ERROR_ALREADY_EXISTS;
}

void DeleteTree(const std::wstring& path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) return;
    const bool isDirectory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    const bool isReparsePoint = (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
    if (!isDirectory || isReparsePoint) {
        SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
        if (isDirectory) RemoveDirectoryW(path.c_str());
        else DeleteFileW(path.c_str());
        return;
    }

    WIN32_FIND_DATAW data{};
    HANDLE find = FindFirstFileW(Join(path, L"*").c_str(), &data);
    if (find != INVALID_HANDLE_VALUE) {
        do {
            if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0) continue;
            DeleteTree(Join(path, data.cFileName));
        } while (FindNextFileW(find, &data));
        FindClose(find);
    }
    SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
    RemoveDirectoryW(path.c_str());
}

void DeleteTreeWithRetry(const std::wstring& path) {
    for (int attempt = 0; attempt < 100; ++attempt) {
        DeleteTree(path);
        if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) return;
        Sleep(100);
    }
}

bool ExtractPayload(const std::wstring& destination) {
    HRSRC resource = FindResourceW(nullptr, MAKEINTRESOURCEW(kPayloadResourceId), RT_RCDATA);
    if (!resource) return false;
    HGLOBAL loaded = LoadResource(nullptr, resource);
    if (!loaded) return false;
    DWORD size = SizeofResource(nullptr, resource);
    const void* bytes = LockResource(loaded);
    if (!bytes || size == 0) return false;

    HANDLE file = CreateFileW(destination.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    BOOL ok = WriteFile(file, bytes, size, &written, nullptr);
    CloseHandle(file);
    return ok && written == size;
}

std::wstring QuoteArgument(const std::wstring& value) {
    if (value.empty()) return L"\"\"";
    if (value.find_first_of(L" \t\n\v\"") == std::wstring::npos) return value;
    std::wstring result = L"\"";
    unsigned backslashes = 0;
    for (wchar_t ch : value) {
        if (ch == L'\\') {
            ++backslashes;
        } else if (ch == L'\"') {
            result.append(backslashes * 2 + 1, L'\\');
            result.push_back(L'\"');
            backslashes = 0;
        } else {
            result.append(backslashes, L'\\');
            backslashes = 0;
            result.push_back(ch);
        }
    }
    result.append(backslashes * 2, L'\\');
    result.push_back(L'\"');
    return result;
}

std::wstring ChildCommandLine(const std::wstring& payload) {
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::wstring command = QuoteArgument(payload);
    if (argv) {
        for (int index = 1; index < argc; ++index) {
            command.push_back(L' ');
            command += QuoteArgument(argv[index]);
        }
        LocalFree(argv);
    }
    return command;
}

void ShowLauncherError(const wchar_t* message) {
    MessageBoxW(nullptr, message, L"MCBEEditor", MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
    if (!mutex) {
        ShowLauncherError(L"\u65e0\u6cd5\u521b\u5efa MCBEEditor \u8fdb\u7a0b\u9501\u3002");
        return 1;
    }
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        MessageBoxW(nullptr, L"MCBEEditor \u5df2\u7ecf\u5728\u8fd0\u884c\u3002", L"MCBEEditor", MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
        CloseHandle(mutex);
        return 0;
    }

    const std::wstring executable = ModulePath();
    const std::wstring root = ParentPath(executable);
    const std::wstring cache = Join(root, L"Cache");
    const std::wstring runtime = Join(cache, L"Runtime");
    const std::wstring bundle = Join(cache, L"DotNetBundle");
    const std::wstring payload = Join(runtime, L"MCBEEditor.Payload.exe");

    DeleteTreeWithRetry(cache);
    if (!EnsureDirectory(runtime) || !EnsureDirectory(bundle)) {
        ShowLauncherError(L"\u65e0\u6cd5\u5728 MCBEEditor.exe \u540c\u7ea7\u76ee\u5f55\u521b\u5efa Cache\u3002\u8bf7\u786e\u8ba4\u5f53\u524d\u76ee\u5f55\u53ef\u5199\u3002");
        ReleaseMutex(mutex);
        CloseHandle(mutex);
        return 2;
    }

    SetEnvironmentVariableW(L"MCBEEDITOR_PORTABLE_ROOT", root.c_str());
    SetEnvironmentVariableW(L"MCBEEDITOR_CACHE_ROOT", cache.c_str());
    SetEnvironmentVariableW(L"DOTNET_BUNDLE_EXTRACT_BASE_DIR", bundle.c_str());
    SetCurrentDirectoryW(root.c_str());

    if (!ExtractPayload(payload)) {
        ShowLauncherError(L"\u65e0\u6cd5\u91ca\u653e MCBEEditor \u8fd0\u884c\u8f7d\u8377\u5230 Cache\u3002\u7a0b\u5e8f\u6587\u4ef6\u53ef\u80fd\u5df2\u635f\u574f\u3002");
        DeleteTreeWithRetry(cache);
        ReleaseMutex(mutex);
        CloseHandle(mutex);
        return 3;
    }

    std::wstring commandLine = ChildCommandLine(payload);
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    BOOL started = CreateProcessW(
        payload.c_str(), commandLine.data(), nullptr, nullptr, FALSE,
        0, nullptr, root.c_str(), &startup, &process);
    if (!started) {
        ShowLauncherError(L"\u65e0\u6cd5\u542f\u52a8 MCBEEditor \u8fd0\u884c\u8f7d\u8377\u3002");
        DeleteTreeWithRetry(cache);
        ReleaseMutex(mutex);
        CloseHandle(mutex);
        return 4;
    }

    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exitCode = 0;
    GetExitCodeProcess(process.hProcess, &exitCode);
    CloseHandle(process.hProcess);

    DeleteTreeWithRetry(cache);
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return static_cast<int>(exitCode);
}
