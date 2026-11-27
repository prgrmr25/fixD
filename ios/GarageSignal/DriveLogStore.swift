import Combine
import Foundation

struct SavedDemoLog: Identifiable {
    let url: URL
    let createdAt: Date
    let fileSize: Int

    var id: URL { url }
}

struct DemoLogRecording {
    fileprivate let url: URL
    fileprivate let writer: FileHandle
    fileprivate(set) var sampleCount = 0
}

@MainActor
final class DriveLogStore: ObservableObject {
    @Published private(set) var savedLogs: [SavedDemoLog] = []
    @Published private(set) var recording: DemoLogRecording?
    @Published private(set) var errorMessage: String?

    private let files = FileManager.default
    private let csvLocale = Locale(identifier: "en_US_POSIX")
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init() {
        reload()
    }

    func start() {
        guard recording == nil else { return }
        errorMessage = nil

        do {
            let filenameFormatter = DateFormatter()
            filenameFormatter.locale = csvLocale
            filenameFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let stamp = filenameFormatter.string(from: .now)
            let suffix = UUID().uuidString.prefix(8)
            let url = try logDirectory()
                .appendingPathComponent("Garage Signal Demo \(stamp)-\(suffix).csv")
            let columns = ["timestamp_utc", "source"] + DemoMetric.allCases.map(\.rawValue)
            let header = columns.joined(separator: ",") + "\r\n"
            try Data(header.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let writer = try FileHandle(forWritingTo: url)
            try writer.seekToEnd()
            recording = DemoLogRecording(url: url, writer: writer)
        } catch {
            errorMessage = "Couldn’t start recording. Check available storage and try again."
            reload()
        }
    }

    func append(_ sample: DemoSample) {
        guard let recording else { return }
        let values = DemoMetric.allCases.map { metric in
            String(format: "%.2f", locale: csvLocale, sample[metric])
        }
        let fields = [timestampFormatter.string(from: sample.timestamp), "simulated"] + values
        let row = Data((fields.joined(separator: ",") + "\r\n").utf8)

        do {
            let originalOffset = try recording.writer.offset()
            do {
                try recording.writer.write(contentsOf: row)
            } catch {
                try? recording.writer.truncate(atOffset: originalOffset)
                throw error
            }
            self.recording?.sampleCount += 1
        } catch {
            stop()
            errorMessage = "Recording stopped because a sample couldn’t be saved."
        }
    }

    func stop() {
        guard let recording else { return }
        self.recording = nil
        do {
            try recording.writer.synchronize()
            try recording.writer.close()
        } catch {
            try? recording.writer.close()
            errorMessage = "The log closed with a storage error. Review the saved CSV before using it."
        }
        reload()
    }

    private func reload() {
        let attributes: Set<URLResourceKey> = [.creationDateKey, .fileSizeKey, .isRegularFileKey]
        do {
            let directory = try logDirectory()
            let urls = try files.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(attributes),
                options: [.skipsHiddenFiles]
            )
            savedLogs = urls.compactMap { url in
                guard url.pathExtension == "csv",
                      url != recording?.url,
                      let info = try? url.resourceValues(forKeys: attributes),
                      info.isRegularFile == true else { return nil }
                return SavedDemoLog(
                    url: url,
                    createdAt: info.creationDate ?? .distantPast,
                    fileSize: info.fileSize ?? 0
                )
            }.sorted { $0.createdAt > $1.createdAt }
        } catch {
            if errorMessage == nil {
                errorMessage = "Couldn’t load saved drive logs."
            }
        }
    }

    private func logDirectory() throws -> URL {
        let applicationSupport = try files.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Demo Logs", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
