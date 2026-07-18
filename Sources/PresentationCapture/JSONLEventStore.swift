import Foundation
import PresentationContracts

public actor JSONLEventRecorder {
    public let url: URL
    private let encoder: JSONEncoder
    private var handle: FileHandle?

    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    public func append(_ event: PresentationEvent) throws {
        if handle == nil {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try FileHandle(forWritingTo: url)
            try handle?.seekToEnd()
        }

        var data = try encoder.encode(event)
        data.append(0x0A)
        try handle?.write(contentsOf: data)
    }

    public func close() throws {
        try handle?.close()
        handle = nil
    }
}

public enum JSONLEventReader {
    public static func read(from url: URL) throws -> [PresentationEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        return try data.split(separator: 0x0A).map { line in
            try decoder.decode(PresentationEvent.self, from: Data(line))
        }
    }
}
