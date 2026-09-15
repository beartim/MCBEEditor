import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class CliTerminal {
    private let input: () -> String?
    private let output: (String) -> Void
    private let error: (String) -> Void
    private let rawInput: Bool
    let useANSI: Bool
    private let useANSIError: Bool

    init(input: @escaping () -> String?, output: @escaping (String) -> Void,
         error: @escaping (String) -> Void, terminalFeatures: Bool) {
        self.input = input
        self.output = output
        self.error = error
        rawInput = terminalFeatures && isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        useANSI = terminalFeatures && isatty(STDOUT_FILENO) == 1
        useANSIError = terminalFeatures && isatty(STDERR_FILENO) == 1
    }

    func readLine(prompt: String, history: [String]) -> String? {
        guard rawInput else {
            output(prompt.trimmingCharacters(in: .whitespaces))
            return input()
        }
        return readRawLine(prompt: prompt, history: history)
    }

    func writeLine(_ text: String) {
        if useANSI { writeRaw(text + "\n") } else { output(text) }
    }

    func writeLine(_ line: WorldCommandOutputLine) {
        guard useANSI else { output(line.text); return }
        writeRaw(color(for: line.style) + line.text + "\u{001B}[0m\n")
    }

    func writeError(_ text: String) {
        guard useANSIError else { error(text); return }
        writeRawError("\u{001B}[31m" + text + "\u{001B}[0m\n")
    }

    func clear() {
        guard useANSI else { return }
        writeRaw("\u{001B}[2J\u{001B}[H")
    }

    private func readRawLine(prompt: String, history: [String]) -> String? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            output(prompt.trimmingCharacters(in: .whitespaces))
            return input()
        }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        raw.c_iflag &= ~tcflag_t(ICRNL | IXON)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            output(prompt.trimmingCharacters(in: .whitespaces))
            return input()
        }
        defer {
            var restore = original
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &restore)
        }

        var buffer = [Character]()
        var cursor = 0
        var historyIndex = history.count
        var draft = ""
        writeRaw(prompt)
        while let byte = readByte() {
            if byte == 10 || byte == 13 {
                writeRaw("\n")
                return String(buffer)
            }
            if byte == 4 && buffer.isEmpty {
                writeRaw("\n")
                return nil
            }
            if byte == 3 {
                writeRaw("^C\n")
                return ""
            }
            if byte == 27 {
                guard readByte() == 91, let code = readByte() else { continue }
                switch code {
                case 65: historyUp(history, index: &historyIndex, draft: &draft, buffer: &buffer, cursor: &cursor)
                case 66: historyDown(history, index: &historyIndex, draft: draft, buffer: &buffer, cursor: &cursor)
                case 67: cursorRight(buffer: buffer, cursor: &cursor)
                case 68: cursorLeft(cursor: &cursor)
                case 51:
                    if readByte() == 126, cursor < buffer.count { buffer.remove(at: cursor); historyIndex = history.count }
                default: break
                }
                redraw(prompt: prompt, buffer: buffer, cursor: cursor)
                continue
            }
            if byte == 127 || byte == 8 {
                if cursor > 0 { buffer.remove(at: cursor - 1); cursor -= 1; historyIndex = history.count; redraw(prompt: prompt, buffer: buffer, cursor: cursor) }
                continue
            }
            guard let text = decodeInput(first: byte) else { continue }
            for character in text {
                buffer.insert(character, at: cursor)
                cursor += 1
            }
            historyIndex = history.count
            redraw(prompt: prompt, buffer: buffer, cursor: cursor)
        }
        writeRaw("\n")
        return buffer.isEmpty ? nil : String(buffer)
    }

    private func historyUp(_ history: [String], index: inout Int, draft: inout String,
                           buffer: inout [Character], cursor: inout Int) {
        guard !history.isEmpty else { return }
        if index >= history.count { draft = String(buffer); index = history.count - 1 }
        else if index > 0 { index -= 1 }
        buffer = Array(history[index]); cursor = buffer.count
    }

    private func historyDown(_ history: [String], index: inout Int, draft: String,
                             buffer: inout [Character], cursor: inout Int) {
        guard !history.isEmpty, index < history.count else { return }
        if index < history.count - 1 { index += 1; buffer = Array(history[index]) }
        else { index = history.count; buffer = Array(draft) }
        cursor = buffer.count
    }

    private func cursorLeft(cursor: inout Int) { if cursor > 0 { cursor -= 1 } }
    private func cursorRight(buffer: [Character], cursor: inout Int) { if cursor < buffer.count { cursor += 1 } }

    private func redraw(prompt: String, buffer: [Character], cursor: Int) {
        writeRaw("\r\u{001B}[2K" + prompt + String(buffer))
        let tail = buffer.count - cursor
        if tail > 0 { writeRaw("\u{001B}[\(tail)D") }
    }

    private func decodeInput(first: UInt8) -> String? {
        if first < 0x80 { return String(UnicodeScalar(first)) }
        let length: Int
        switch first {
        case 0xC2...0xDF: length = 2
        case 0xE0...0xEF: length = 3
        case 0xF0...0xF4: length = 4
        default: return nil
        }
        var bytes = [first]
        while bytes.count < length {
            guard let next = readByte(), next & 0xC0 == 0x80 else { return nil }
            bytes.append(next)
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        #if os(Linux)
        let count = Glibc.read(STDIN_FILENO, &byte, 1)
        #else
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        #endif
        return count == 1 ? byte : nil
    }

    private func color(for style: WorldCommandOutputStyle) -> String {
        switch style {
        case .localPlayer: return "\u{001B}[33m"
        case .onlinePlayer: return "\u{001B}[34m"
        case .entity: return "\u{001B}[36m"
        case .block: return "\u{001B}[34m"
        case .blockEntity: return "\u{001B}[35m"
        case .success: return "\u{001B}[32m"
        }
    }

    private func writeRaw(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
    private func writeRawError(_ text: String) { FileHandle.standardError.write(Data(text.utf8)) }
}
