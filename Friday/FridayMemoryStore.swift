//
//  FridayMemoryStore.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import Foundation

actor FridayMemoryStore {
    static let shared = FridayMemoryStore()

    private static let saveQueue = DispatchQueue(label: "com.vedpanse.Friday.memory-save", qos: .utility)

    private let fileURL: URL
    private var cachedMemories: [MemoryRecord]?

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Friday", directoryHint: .isDirectory)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Friday", directoryHint: .isDirectory)

        self.fileURL = baseURL.appending(path: "memory.json", directoryHint: .notDirectory)
    }

    func loadMemories() async -> [MemoryRecord] {
        if let cachedMemories {
            return cachedMemories
        }

        do {
            let fileURL = fileURL
            let envelope = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder.friday.decode(MemoryEnvelope.self, from: data)
            }.value
            cachedMemories = envelope.memories
            return envelope.memories
        } catch {
            cachedMemories = []
            return []
        }
    }

    func saveMemoryIfNeeded(_ text: String) async -> [MemoryRecord] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count >= 8 else {
            return await loadMemories()
        }

        var memories = await loadMemories()
        let normalizedCandidate = trimmedText.normalizedMemoryText

        if memories.contains(where: { $0.text.normalizedMemoryText == normalizedCandidate }) {
            return memories
        }

        memories.insert(MemoryRecord(text: trimmedText, source: .conversation), at: 0)
        if memories.count > 80 {
            memories = Array(memories.prefix(80))
        }

        await save(memories)
        return memories
    }

    private func save(_ memories: [MemoryRecord]) async {
        let fileURL = fileURL
        let envelope = MemoryEnvelope(version: 1, memories: memories)
        cachedMemories = memories

        Self.saveQueue.async {
            do {
                let directoryURL = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let data = try JSONEncoder.friday.encode(envelope)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                NSLog("Friday failed to save memory: \(error.localizedDescription)")
            }
        }
    }
}

private nonisolated struct MemoryEnvelope: Codable {
    let version: Int
    let memories: [MemoryRecord]
}

private nonisolated extension JSONDecoder {
    static var friday: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private nonisolated extension JSONEncoder {
    static var friday: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private nonisolated extension String {
    var normalizedMemoryText: String {
        lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
