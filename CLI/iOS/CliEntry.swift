import Foundation
import Darwin

private var interrupted: sig_atomic_t = 0

@main
struct MCBEEditorCliEntry {
    static func main() {
        let previous = signal(SIGINT) { _ in interrupted = 1 }
        CliSharedCommandStore.prepareDefault(error: MCBEEditorCli.writeError)
        let result = MCBEEditorCli.run(Array(CommandLine.arguments.dropFirst()), cancelled: { interrupted != 0 }, terminalFeatures: true)
        signal(SIGINT, previous)
        exit(result)
    }
}
