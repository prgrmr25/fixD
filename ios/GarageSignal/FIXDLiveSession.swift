import CoreBluetooth
import DiagnosticsCore
import Foundation

/// One already connected adapter. The inspector retains ownership of the peripheral delegate.
@MainActor
final class FIXDLiveSession {
    enum Failure: LocalizedError {
        case disconnected
        case unsupportedCharacteristics
        case alreadyStarted
        case notReady
        case queueFull
        case subscription(String)
        case writeCapacity
        case write(String)
        case timeout(String)
        case invalidResponse(String)
        case rejectedSetup(String)
        case moduleAddressRequired
        case cancelled

        var errorDescription: String? {
            switch self {
            case .disconnected: "The adapter is disconnected."
            case .unsupportedCharacteristics: "The selected GATT characteristics do not support this session."
            case .alreadyStarted: "An adapter session has already started on this connection."
            case .notReady: "Finish adapter setup before reading diagnostics."
            case .queueFull: "The adapter is already waiting on too many reads."
            case .subscription(let reason): "Couldn’t subscribe to adapter replies. \(reason)"
            case .writeCapacity: "The adapter cannot accept a complete command packet."
            case .write(let reason): "The Bluetooth write failed. \(reason)"
            case .timeout(let command): "The adapter timed out while handling \(command). Reconnect to try again."
            case .invalidResponse(let reason): "Invalid adapter reply. \(reason)"
            case .rejectedSetup(let command): "The adapter did not accept \(command)."
            case .moduleAddressRequired: "The Honda read needs a specific module address."
            case .cancelled: "The adapter session was cancelled."
            }
        }
    }

    private enum Phase {
        case idle
        case configuring
        case ready
        case invalidated(Failure)
    }

    private enum AdapterCommand: String {
        case reset = "ATZ"
        case defaults = "ATD"
        case echoOff = "ATE0"
        case linefeedsOff = "ATL0"
        case spacesOff = "ATS0"
        case headersOn = "ATH1"
        case autoProtocol = "ATSP0"
        case protocolNumber = "ATDPN"

        static let standardConfiguration: [Self] = [
            .defaults, .echoOff, .linefeedsOff, .spacesOff, .headersOn, .autoProtocol,
        ]

        var bytes: [UInt8] { Array((rawValue + "\r").utf8) }

        func accepted(_ reply: String) -> Bool {
            let rows = reply.split(whereSeparator: \.isNewline).map { line in
                line.trimmingCharacters(in: .whitespaces).uppercased()
            }.filter { row in
                !row.isEmpty && row.filter { !$0.isWhitespace } != rawValue
            }
            if self == .reset {
                return !rows.isEmpty && rows.allSatisfy {
                    !$0.contains("?") && !$0.contains("ERROR") && $0 != "STOPPED"
                }
            }
            return rows == ["OK"]
        }
    }

    private struct Exchange {
        let id: UUID
        let bytes: Data
        let command: String
        let timeout: Duration
        let continuation: CheckedContinuation<String, Error>
        var written = false
        var acknowledged = false
        var reply: String?
    }

    private let peripheral: CBPeripheral
    private let receive: CBCharacteristic
    private let transmit: CBCharacteristic
    private let writeType: CBCharacteristicWriteType

    private var phase = Phase.idle
    private var subscribed = false
    private var subscription: CheckedContinuation<Void, Error>?
    private var queue: [Exchange] = []
    private var active: Exchange?
    private var deadline: Task<Void, Never>?
    private var framer = ASCIIPromptFramer()

    private var terminalFailure: Failure? {
        if case .invalidated(let failure) = phase {
            return failure
        }
        return nil
    }

    var isInvalidated: Bool { terminalFailure != nil }
    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    init(peripheral: CBPeripheral, receive: CBCharacteristic, transmit: CBCharacteristic) throws {
        guard peripheral.state == .connected else { throw Failure.disconnected }
        guard receive !== transmit,
              let service = receive.service,
              transmit.service === service,
              service.peripheral === peripheral,
              !receive.properties.intersection([.notify, .indicate]).isEmpty else {
            throw Failure.unsupportedCharacteristics
        }

        if transmit.properties.contains(.write) {
            writeType = .withResponse
        } else if transmit.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else {
            throw Failure.unsupportedCharacteristics
        }

        self.peripheral = peripheral
        self.receive = receive
        self.transmit = transmit
    }

    /// Sets the adapter’s local defaults, then selects automatic protocol detection.
    /// The caller can request supported PIDs first and query ATDPN once that reply arrives.
    func start() async throws {
        guard case .idle = phase else { throw terminalFailure ?? Failure.alreadyStarted }
        phase = .configuring

        do {
            try await subscribe()
            try await configureAdapter([.reset] + AdapterCommand.standardConfiguration)
            try Task.checkCancellation()
            guard case .configuring = phase else { throw terminalFailure ?? Failure.notReady }
            phase = .ready
        } catch {
            invalidate(because: error as? Failure ?? .cancelled)
            throw error
        }
    }

    /// Returns the raw prompt-delimited reply for a fixed read-only request.
    func read(_ request: DiagnosticRequest) async throws -> String {
        guard case .ready = phase else { throw terminalFailure ?? Failure.notReady }
        if case .hondaData = request { throw Failure.moduleAddressRequired }
        let timeout: Duration
        if case .currentData(.supported01Through20) = request {
            timeout = .seconds(20)
        } else {
            timeout = .seconds(10)
        }
        return try await exchange(ASCIIPromptFramer.encode(request), timeout: timeout)
    }

    struct ModuleExchange {
        let directedControl: String?
        let hondaReply: String
    }

    /// Selects one allowlisted module and restores standard configuration before handing the link back.
    func readModule(
        _ probe: HondaModuleProbe,
        checkDirectedOBD: Bool,
        trace: (String) -> Void
    ) async throws -> ModuleExchange {
        guard case .ready = phase else { throw terminalFailure ?? Failure.notReady }
        phase = .configuring

        do {
            // Some ELM-compatible adapters reject optional commands. The defaults
            // still supply priority 0x18, and the parser always checks the responder.
            try await selectModuleSetting("ATCP18", optional: true, trace: trace)
            let header = "ATSH" + String(probe.requestCANID.suffix(6))
            try await selectModuleSetting(header, optional: false, trace: trace)
            try await selectModuleSetting("ATCRA" + probe.responseCANID, optional: true, trace: trace)

            let control = DiagnosticRequest.currentData(.supported01Through20)
            var directedControl: String?
            if checkDirectedOBD {
                directedControl = try await exchange(ASCIIPromptFramer.encode(control), timeout: .seconds(10))
                if let directedControl {
                    trace(Self.traceLine("Directed standard 0100", reply: directedControl))
                }
            }

            let request = ASCIIPromptFramer.encode(.hondaData(probe))
            let reply = try await exchange(request, timeout: .seconds(10))
            let command = String(decoding: request.dropLast(), as: UTF8.self)
            trace(Self.traceLine("Honda read " + command, reply: reply))

            try await configureAdapter(AdapterCommand.standardConfiguration)
            trace("Adapter acknowledged standard configuration restore.")

            let restored = try await exchange(ASCIIPromptFramer.encode(control), timeout: .seconds(10))
            trace(Self.traceLine("Functional standard 0100 after restore", reply: restored))
            let responders = HondaModuleProbe.functionalControlResponders(reply: restored)
            if responders.isEmpty {
                trace("No valid standard 29-bit responders confirmed after restore.")
            } else {
                trace("Standard responders after restore: " + responders.joined(separator: ", "))
            }

            try Task.checkCancellation()
            guard case .configuring = phase else { throw terminalFailure ?? Failure.notReady }
            phase = .ready
            return ModuleExchange(directedControl: directedControl, hondaReply: reply)
        } catch {
            // A timed-out request or failed restore must not leave a usable targeted header.
            invalidate(because: error as? Failure ?? .cancelled)
            throw error
        }
    }

    private func selectModuleSetting(_ command: String, optional: Bool, trace: (String) -> Void) async throws {
        let reply = try await exchange(Array((command + "\r").utf8), timeout: .seconds(5))
        trace(Self.traceLine(command, reply: reply))
        let status = reply.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces).uppercased()
        }.filter { !$0.isEmpty && $0.filter { !$0.isWhitespace } != command }
        guard status == ["OK"] || (optional && status == ["?"]) else {
            throw Failure.rejectedSetup(command)
        }
    }

    private static func traceLine(_ label: String, reply: String) -> String {
        let lines = reply.split(whereSeparator: \.isNewline)
        return ([label + ":"] + lines.map { "  " + String($0) }).joined(separator: "\n")
    }

    private func configureAdapter(_ commands: [AdapterCommand]) async throws {
        for command in commands {
            let timeout: Duration = command == .reset ? .seconds(8) : .seconds(5)
            let reply = try await exchange(command.bytes, timeout: timeout)
            guard command.accepted(reply) else { throw Failure.rejectedSetup(command.rawValue) }
        }
    }

    func readAdapterProtocol() async throws -> String {
        guard case .ready = phase else { throw terminalFailure ?? Failure.notReady }
        return try await exchange(AdapterCommand.protocolNumber.bytes, timeout: .seconds(5))
    }

    func invalidate() {
        invalidate(because: .disconnected)
    }

    func didUpdateNotificationState(for characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === receive, subscribed, !isInvalidated else { return }
        if let error {
            invalidate(because: .subscription(error.localizedDescription))
        } else if !receive.isNotifying {
            invalidate(because: .subscription("The notification channel is inactive."))
        } else if let subscription {
            self.subscription = nil
            cancelDeadline()
            subscription.resume()
        }
    }

    func didUpdateValue(for characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === receive, subscribed, !isInvalidated else { return }
        if let error {
            invalidate(because: .invalidResponse(error.localizedDescription))
            return
        }
        guard active?.written == true, let bytes = characteristic.value else { return }

        do {
            let replies = try framer.consume(Array(bytes)).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !replies.isEmpty else { return }
            guard replies.count == 1, active?.reply == nil else {
                invalidate(because: .invalidResponse("The adapter returned multiple replies for one request."))
                return
            }
            active?.reply = replies[0]
            finishExchangeIfReady()
        } catch {
            invalidate(because: .invalidResponse("The response exceeded the framing limits or contained non-ASCII data."))
        }
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === transmit, writeType == .withResponse, active?.written == true else { return }
        if let error {
            invalidate(because: .write(error.localizedDescription))
        } else {
            active?.acknowledged = true
            finishExchangeIfReady()
        }
    }

    func peripheralIsReadyToSendWriteWithoutResponse() {
        guard writeType == .withoutResponse else { return }
        writeActiveExchange()
    }

    private func subscribe() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if peripheral.state != .connected {
                    continuation.resume(throwing: Failure.disconnected)
                } else {
                    subscribed = true
                    if receive.isNotifying {
                        continuation.resume()
                    } else {
                        subscription = continuation
                        armDeadline(.seconds(6), failure: .subscription("The adapter did not confirm notifications in time."))
                        peripheral.setNotifyValue(true, for: receive)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.invalidate(because: .cancelled)
            }
        }
    }

    private func exchange(_ command: [UInt8], timeout: Duration) async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if let failure = terminalFailure {
                    continuation.resume(throwing: failure)
                } else if queue.count >= 32 {
                    continuation.resume(throwing: Failure.queueFull)
                } else {
                    queue.append(Exchange(
                        id: id,
                        bytes: Data(command),
                        command: String(decoding: command.dropLast(), as: UTF8.self),
                        timeout: timeout,
                        continuation: continuation
                    ))
                    startNextExchange()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelExchange(id)
            }
        }
    }

    private func startNextExchange() {
        guard active == nil, !queue.isEmpty, !isInvalidated else { return }
        let next = queue.removeFirst()
        framer.reset()
        active = next
        armDeadline(next.timeout, failure: .timeout(next.command))
        writeActiveExchange()
    }

    private func writeActiveExchange() {
        guard let active, !active.written else { return }
        guard peripheral.state == .connected else {
            invalidate(because: .disconnected)
            return
        }
        guard receive.isNotifying else {
            invalidate(because: .subscription("The notification channel is inactive."))
            return
        }
        guard active.bytes.count <= peripheral.maximumWriteValueLength(for: writeType) else {
            invalidate(because: .writeCapacity)
            return
        }
        if writeType == .withoutResponse && !peripheral.canSendWriteWithoutResponse {
            return
        }

        self.active?.written = true
        self.active?.acknowledged = writeType == .withoutResponse
        peripheral.writeValue(active.bytes, for: transmit, type: writeType)
    }

    private func finishExchangeIfReady() {
        guard let active, active.acknowledged, let reply = active.reply else { return }
        self.active = nil
        cancelDeadline()
        active.continuation.resume(returning: reply)
        startNextExchange()
    }

    private func cancelExchange(_ id: UUID) {
        if active?.id == id {
            invalidate(because: .cancelled)
        } else if let index = queue.firstIndex(where: { $0.id == id }) {
            queue.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }

    private func armDeadline(_ duration: Duration, failure: Failure) {
        cancelDeadline()
        deadline = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.invalidate(because: failure)
        }
    }

    private func cancelDeadline() {
        deadline?.cancel()
        deadline = nil
    }

    private func invalidate(because failure: Failure) {
        guard !isInvalidated else { return }
        phase = .invalidated(failure)
        cancelDeadline()
        framer.reset()

        let pending = queue
        let active = self.active
        let subscription = self.subscription
        queue.removeAll()
        self.active = nil
        self.subscription = nil

        // A timed-out link stays invalid even if a delayed ACK, prompt, or notification arrives.
        if subscribed && peripheral.state == .connected {
            peripheral.setNotifyValue(false, for: receive)
        }
        subscribed = false
        subscription?.resume(throwing: failure)
        active?.continuation.resume(throwing: failure)
        for entry in pending {
            entry.continuation.resume(throwing: failure)
        }
    }
}
