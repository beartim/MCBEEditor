#!/usr/bin/env python3
"""Run real Commands stores with changing help providers and real temporary files.

The stored ReadMe must stay fixed even when runtime help changes. Preparation
must restore ReadMe verbatim without creating or changing the user Command.txt.
Only path and unused command-reading dependencies are substituted.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="mcbe-fixed-readme-") as temporary:
    work = Path(temporary)
    project = work / "FixedReadMe.csproj"
    project.write_text(f'''<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup>
    <Compile Include="{ROOT / 'Windows/MCBEEditor.Desktop/SharedCommandFileStore.cs'}" />
    <Compile Include="{ROOT / 'CLI/Windows/CliSharedCommandStore.cs'}" />
  </ItemGroup>
</Project>
''')
    (work / "Program.cs").write_text(r'''
using MCBEEditor.Desktop;
using MCBEEditor.Cli;

static void Check(bool value, string message) { if (!value) throw new Exception(message); }
static void Verify(Action prepare, string directory, string label, string expectedSnapshot)
{
    var command = Path.Combine(directory, "Command.txt");
    var readMe = Path.Combine(directory, "ReadMe.txt");
    prepare();
    Check(!File.Exists(command), label + " created Command.txt");
    var initial = File.ReadAllBytes(readMe);
    Check(initial.SequenceEqual(File.ReadAllBytes(expectedSnapshot)), label + " differs from shipped fixed ReadMe");
    var text = System.Text.Encoding.UTF8.GetString(initial);
    Check(!text.Contains("RUNTIME_HELP_"), label + " assembled ReadMe from runtime help");
    Check(text.Contains("dimension query") && text.Contains("tickingarea") && text.Contains("weather"),
        label + " omitted fixed command instructions");
    var owned = new byte[] { 0xef, 0xbb, 0xbf, 0x61, 0x0d, 0x0a, 0xff };
    File.WriteAllBytes(command, owned);
    File.WriteAllText(readMe, "user edit");
    CommandHelpCatalog.Generation++;
    prepare();
    Check(File.ReadAllBytes(readMe).SequenceEqual(initial), label + " did not restore fixed ReadMe");
    Check(File.ReadAllBytes(command).SequenceEqual(owned), label + " changed user Command.txt");
    Console.WriteLine(label + ": fixed ReadMe restored; Command.txt preserved");
}
Verify(SharedCommandFileStore.PrepareSharedDirectory, PortablePaths.CommandsPath, "Windows GUI",
    Path.Combine(args[0], "Windows", "Commands", "ReadMe.txt"));
Verify(() => CliSharedCommandStore.Prepare(CliPortablePaths.CommandsDirectory),
    CliPortablePaths.CommandsDirectory, "Windows CLI",
    Path.Combine(args[0], "WindowsCLI", "Commands", "ReadMe.txt"));

namespace MCBEEditor.Desktop
{
    static class PortablePaths { public static string CommandsPath => Path.Combine(AppContext.BaseDirectory, "gui"); }
    static class CommandHelpCatalog
    {
        public static int Generation;
        public static string AllUsageText => "RUNTIME_HELP_" + Generation;
    }
}
namespace MCBEEditor.Cli
{
    static class CliPortablePaths { public static string CommandsDirectory => Path.Combine(AppContext.BaseDirectory, "cli"); }
    record CliCommandLine(int LineNumber, string Text);
    static class CliCommandFile { public static IReadOnlyList<CliCommandLine> Read(string path) => throw new NotSupportedException(); }
    static class CliStructureFileCommand { public static string Usage => "RUNTIME_HELP_STRUCTURE_" + MCBEEditor.Desktop.CommandHelpCatalog.Generation; }
}
''')
    dotnet = shutil.which("dotnet") or "dotnet"
    run(dotnet, "build", str(project), "-m:1", "-p:BuildInParallel=false",
        "-p:UseSharedCompilation=false", "--nologo", "-v:q")
    run(dotnet, str(work / "bin/Debug/net10.0/FixedReadMe.dll"), str(ROOT / "Docs/FixedReadMe"))

    swift = work / "FixedReadMe.swift"
    swift.write_text(r'''
import Foundation
// Substitute only the Documents root; directory creation, file reads and all
// production Data.write calls still use the real filesystem.
final class FileManager {
    static let `default` = FileManager()
    func urls(for directory: Foundation.FileManager.SearchPathDirectory,
              in domain: Foundation.FileManager.SearchPathDomainMask) -> [URL] {
        [URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)]
    }
    func fileExists(atPath path: String) -> Bool {
        Foundation.FileManager.default.fileExists(atPath: path)
    }
    func createDirectory(at url: URL, withIntermediateDirectories: Bool,
                         attributes: [FileAttributeKey: Any]? = nil) throws {
        try Foundation.FileManager.default.createDirectory(at: url,
            withIntermediateDirectories: withIntermediateDirectories, attributes: attributes)
    }
}
struct CliCommandLine { let lineNumber: Int; let text: String }
enum CliCommandFile { static func read(_ path: String) throws -> [CliCommandLine] { fatalError("unused") } }
enum WorldCommandParser {
    static var generation = 0
    static func helpText() -> String { "RUNTIME_HELP_\(generation)" }
}
enum CliStructureFileCommand { static var usage: String { "RUNTIME_HELP_STRUCTURE_\(WorldCommandParser.generation)" } }
@main struct ReadMeTest {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try CliSharedCommandStore.prepare(at: directory)
        precondition(!CliSharedCommandStore.commandFileExists(in: directory), "Apple CLI created Command.txt")
        let readMe = CliSharedCommandStore.readMeFile(in: directory)
        let initial = try Data(contentsOf: readMe)
        let snapshots = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let cliSnapshot = try Data(contentsOf: snapshots.appendingPathComponent("AppleCLI/Commands/ReadMe.txt"))
        precondition(initial == cliSnapshot, "Apple CLI differs from shipped fixed ReadMe")
        let text = String(decoding: initial, as: UTF8.self)
        precondition(!text.contains("RUNTIME_HELP_"), "Apple CLI assembled ReadMe from runtime help")
        precondition(text.contains("dimension query") && text.contains("tickingarea") && text.contains("weather"))
        let command = CliSharedCommandStore.commandFile(in: directory)
        let owned = Data([0xef, 0xbb, 0xbf, 0x61, 0x0d, 0x0a, 0xff])
        try owned.write(to: command)
        try Data("user edit".utf8).write(to: readMe)
        WorldCommandParser.generation += 1
        try CliSharedCommandStore.prepare(at: directory)
        let restored = try Data(contentsOf: readMe)
        let unchanged = try Data(contentsOf: command)
        precondition(restored == initial, "Apple CLI did not restore fixed ReadMe")
        precondition(unchanged == owned, "Apple CLI changed user Command.txt")
        print("Apple CLI: fixed ReadMe restored; Command.txt preserved")

        SharedCommandFileStore.prepareSharedDirectory()
        let guiDirectory = SharedCommandFileStore.commandsDirectoryURL!
        let guiCommand = guiDirectory.appendingPathComponent("Command.txt")
        let guiReadMe = guiDirectory.appendingPathComponent("ReadMe.txt")
        precondition(!FileManager.default.fileExists(atPath: guiCommand.path), "iOS GUI created Command.txt")
        let guiInitial = try Data(contentsOf: guiReadMe)
        let guiSnapshot = try Data(contentsOf: snapshots.appendingPathComponent("iOS/Commands/ReadMe.txt"))
        precondition(guiInitial == guiSnapshot, "iOS GUI differs from shipped fixed ReadMe")
        let guiText = String(decoding: guiInitial, as: UTF8.self)
        precondition(guiText.contains("dimension query") && guiText.contains("tickingarea") && guiText.contains("weather"))
        try owned.write(to: guiCommand)
        try Data("user edit".utf8).write(to: guiReadMe)
        SharedCommandFileStore.prepareSharedDirectory()
        let guiRestored = try Data(contentsOf: guiReadMe)
        let guiUnchanged = try Data(contentsOf: guiCommand)
        precondition(guiRestored == guiInitial, "iOS GUI did not restore fixed ReadMe")
        precondition(guiUnchanged == owned, "iOS GUI changed user Command.txt")
        print("iOS GUI store: fixed ReadMe restored; Command.txt preserved")
    }
}
''')
    executable = work / "swift-readme-test"
    run(shutil.which("swiftc") or "swiftc", "-o", str(executable), str(swift),
        str(ROOT / "CLI/iOS/CliSharedCommandStore.swift"),
        str(ROOT / "Sources/Support/SharedCommandFileStore.swift"),
        str(ROOT / "Sources/Support/Errors.swift"))
    run(str(executable), str(work / "apple-cli"), str(ROOT / "Docs/FixedReadMe"))

print("Fixed ReadMe runtime independence checks passed.")
