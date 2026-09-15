#include <windows.h>
#include <shellapi.h>
#include <cstdio>
#include <string>
#include <vector>

namespace {
constexpr int kPayloadResourceId = 101;

std::wstring Join(const std::wstring& left, const std::wstring& right) {
    if (left.empty()) return right;
    if (left.back() == L'\\' || left.back() == L'/') return left + right;
    return left + L"\\" + right;
}

std::wstring ModulePath() {
    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size()) return {};
    return std::wstring(buffer.data(), length);
}

std::wstring ParentPath(const std::wstring& path) {
    const auto slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"." : path.substr(0, slash);
}

bool EnsureDirectory(const std::wstring& path) {
    if (path.empty()) return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) return (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    const auto parent = ParentPath(path);
    if (parent != path && !parent.empty() && parent != L"." && !EnsureDirectory(parent)) return false;
    return CreateDirectoryW(path.c_str(), nullptr) != 0 || GetLastError() == ERROR_ALREADY_EXISTS;
}

void DeleteTree(const std::wstring& path) {
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) return;
    const bool directory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    const bool reparse = (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
    if (!directory || reparse) {
        SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
        if (directory) RemoveDirectoryW(path.c_str());
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
    for (int attempt = 0; attempt < 50; ++attempt) {
        DeleteTree(path);
        if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) return;
        Sleep(50);
    }
}

bool ExtractPayload(const std::wstring& destination) {
    HRSRC resource = FindResourceW(nullptr, MAKEINTRESOURCEW(kPayloadResourceId), RT_RCDATA);
    if (!resource) return false;
    HGLOBAL loaded = LoadResource(nullptr, resource);
    if (!loaded) return false;
    const DWORD size = SizeofResource(nullptr, resource);
    const void* bytes = LockResource(loaded);
    if (!bytes || size == 0) return false;

    HANDLE file = CreateFileW(destination.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    const BOOL ok = WriteFile(file, bytes, size, &written, nullptr);
    CloseHandle(file);
    return ok && written == size;
}

std::wstring QuoteArgument(const std::wstring& value) {
    if (value.empty()) return L"\"\"";
    if (value.find_first_of(L" \t\n\v\"") == std::wstring::npos) return value;
    std::wstring result = L"\"";
    unsigned backslashes = 0;
    for (const wchar_t ch : value) {
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

void LauncherError(const char* message) {
    std::fprintf(stderr, "mcbe-cli launcher: %s\n", message);
    std::fflush(stderr);
}

BOOL WINAPI LauncherControlHandler(DWORD type) {
    // The managed child shares this console and owns SIGINT/CTRL+C cancellation.
    // Keep the wrapper alive long enough to observe the child exit and clean only its runtime directory.
    return type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT;
}

void TryRemoveEmpty(const std::wstring& path) {
    RemoveDirectoryW(path.c_str());
}
}

int wmain() {
    const std::wstring executable = ModulePath();
    if (executable.empty()) {
        LauncherError("cannot resolve the launcher path");
        return 3;
    }

    const std::wstring root = ParentPath(executable);
    const std::wstring cache = Join(root, L"Cache");
    const std::wstring runtimeRoot = Join(cache, L"Runtime");
    const std::wstring runtime = Join(runtimeRoot, std::to_wstring(GetCurrentProcessId()));
    const std::wstring bundle = Join(runtime, L"DotNetBundle");
    const std::wstring payload = Join(runtime, L"mcbe-cli.payload.exe");

    DeleteTreeWithRetry(runtime);
    if (!EnsureDirectory(runtime) || !EnsureDirectory(bundle)) {
        LauncherError("cannot create Cache\\Runtime beside mcbe-cli.exe; check directory permissions");
        return 3;
    }

    if (!SetEnvironmentVariableW(L"MCBEEDITOR_PORTABLE_ROOT", root.c_str()) ||
        !SetEnvironmentVariableW(L"MCBEEDITOR_CACHE_ROOT", cache.c_str()) ||
        !SetEnvironmentVariableW(L"DOTNET_BUNDLE_EXTRACT_BASE_DIR", bundle.c_str())) {
        LauncherError("cannot configure portable runtime environment");
        DeleteTreeWithRetry(runtime);
        return 3;
    }
    if (!ExtractPayload(payload)) {
        LauncherError("cannot extract the embedded managed payload; the executable may be damaged");
        DeleteTreeWithRetry(runtime);
        return 3;
    }

    SetConsoleCtrlHandler(LauncherControlHandler, TRUE);
    std::wstring commandLine = ChildCommandLine(payload);
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION process{};
    const BOOL started = CreateProcessW(
        payload.c_str(), commandLine.data(), nullptr, nullptr, TRUE,
        CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr, &startup, &process);
    if (!started) {
        LauncherError("cannot start the embedded managed payload");
        SetConsoleCtrlHandler(LauncherControlHandler, FALSE);
        DeleteTreeWithRetry(runtime);
        TryRemoveEmpty(runtimeRoot);
        TryRemoveEmpty(cache);
        return 3;
    }

    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exitCode = 1;
    if (!GetExitCodeProcess(process.hProcess, &exitCode)) exitCode = 1;
    CloseHandle(process.hProcess);
    SetConsoleCtrlHandler(LauncherControlHandler, FALSE);

    // Never recursively remove Cache: failed/--keep-work world sessions deliberately preserve work there.
    // Delete only this launcher's private extraction directory and opportunistically remove empty parents.
    DeleteTreeWithRetry(runtime);
    TryRemoveEmpty(runtimeRoot);
    TryRemoveEmpty(Join(cache, L"Worlds"));
    TryRemoveEmpty(cache);
    return static_cast<int>(exitCode);
}
