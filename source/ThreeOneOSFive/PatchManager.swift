import Foundation
import CommonCrypto
import ZIPFoundation

/// Loads bundled patch-package resources for display and in-memory access.
/// This class does not apply patches to a running game process.
final class PatchManager {
    static let shared = PatchManager()

    private let aesKey = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
    private let lock = NSLock()
    private(set) var memoryPatches: [String: Data] = [:]

    private init() {}

    func countFiles(for module: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return memoryPatches.keys.filter {
            $0.localizedCaseInsensitiveContains(module)
        }.count
    }

    /// Returns bundled package filenames matching the selected UI category.
    /// For Free Fire TH, the project only identifies file (24) as AimBot;
    /// the other numbered packages have no category metadata available here.
    func getFilesInCategory(_ category: PatchCategory, game: GameTarget) -> [String] {
        let names: [String]
        lock.lock()
        names = Array(memoryPatches.keys)
        lock.unlock()

        let aliases: [String]
        switch category {
        case .aimBody: aliases = ["aimbody", "aim-body"]
        case .aimLock: aliases = ["aimlock", "aim-lock"]
        case .aimBot:  aliases = ["aimbot", "aim-bot"]
        case .antiban: aliases = ["antiban", "anti-ban"]
        case .nheTam:  aliases = ["nhetam", "nhe-tam", "nhẹ tâm"]
        case .other:   aliases = []
        }

        return names.filter { key in
            let filename = (key as NSString).lastPathComponent
            let lower = filename.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            // "Khác" contains files that do not match any supported category.
            if category == .other {
                switch game {
                case .freeFireVN:
                    let knownAliases = ["aimbody", "aim-body", "aimlock", "aim-lock",
                                        "aimbot", "aim-bot", "antiban", "anti-ban",
                                        "nhetam", "nhe-tam", "nhẹ tâm"]
                    return !knownAliases.contains {
                        lower.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
                    }
                case .freeFireTH:
                    let knownTHFiles = (20...24).map { "ogios file (\($0))" }
                    return !knownTHFiles.contains { lower.contains($0) }
                }
            }

            switch game {
            case .freeFireVN:
                return aliases.contains { lower.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)) }
            case .freeFireTH:
                if category == .aimBot {
                    return lower.contains("ogios file (24)")
                }
                return false
            }
        }.map { ($0 as NSString).lastPathComponent }.sorted()
    }

    /// Loads .3105 package files copied into the app bundle by the Xcode Resources phase.
    /// Also supports the older sys_cache.dat archive when that resource is present.
    func initializePatches() {
        var loaded: [String: Data] = [:]

        if let urls = Bundle.main.urls(forResourcesWithExtension: "3105", subdirectory: nil) {
            for url in urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                loaded[url.lastPathComponent] = data
            }
        }

        if loaded.isEmpty,
           let datURL = Bundle.main.url(forResource: "sys_cache", withExtension: "dat"),
           let fileData = try? Data(contentsOf: datURL),
           let archiveData = decryptLegacyCache(fileData),
           let extracted = extractArchive(archiveData) {
            loaded.merge(extracted) { _, new in new }
        }

        lock.lock()
        memoryPatches = loaded
        lock.unlock()

        print("Loaded \(loaded.count) bundled patch package(s) into memory")
    }

    private func decryptLegacyCache(_ fileData: Data) -> Data? {
        guard fileData.count > 40 else { return nil }
        let payload = fileData.dropFirst(8)
        let ivBytes = payload.prefix(32)
        guard let ivString = String(data: ivBytes, encoding: .utf8) else { return nil }
        let cipherData = Data(payload.dropFirst(32))
        return decryptAES(data: cipherData, key: aesKey, iv: ivString)
    }

    private func decryptAES(data: Data, key: String, iv: String) -> Data? {
        let keyData = Data(hex: key)
        let ivData = Data(hex: iv)
        guard keyData.count == kCCKeySizeAES256,
              ivData.count == kCCBlockSizeAES128,
              !data.isEmpty else { return nil }

        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var decryptedCount: size_t = 0

        let status = buffer.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                ivData.withUnsafeBytes { ivBytes in
                    keyData.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyData.count,
                            ivBytes.baseAddress,
                            input.baseAddress, data.count,
                            output.baseAddress, bufferSize,
                            &decryptedCount
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        buffer.removeSubrange(decryptedCount..<buffer.count)
        return buffer
    }

    private func extractArchive(_ data: Data) -> [String: Data]? {
        guard let archive = Archive(data: data, accessMode: .read) else { return nil }
        var result: [String: Data] = [:]
        for entry in archive where entry.type == .file {
            var extracted = Data()
            do {
                _ = try archive.extract(entry) { extracted.append($0) }
                result[entry.path] = extracted
            } catch {
                print("Unable to extract bundled entry \(entry.path): \(error)")
            }
        }
        return result
    }
}

private extension Data {
    init(hex: String) {
        self.init()
        let characters = Array(hex)
        guard characters.count.isMultiple(of: 2) else { return }
        for index in stride(from: 0, to: characters.count, by: 2) {
            let pair = String(characters[index...index + 1])
            guard let byte = UInt8(pair, radix: 16) else { self.removeAll(); return }
            append(byte)
        }
    }
}
