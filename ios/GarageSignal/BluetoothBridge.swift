import CoreBluetooth
import Foundation
import SwiftUI

@MainActor
struct AdapterInspectorView: View {
    @ObservedObject var bridge: BluetoothBridge

    var body: some View {
        List {
            Section {
                Label("Bluetooth diagnosis", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Text("Select your FIXD or FIXD2 to inspect its Bluetooth connection and start a read-only vehicle scan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(bridge.status)
                    .font(.subheadline)
                    .accessibilityLabel("Status: \(bridge.status)")

                if bridge.isScanning {
                    Button("Stop Scan", systemImage: "stop.circle", action: bridge.stopScan)
                } else if bridge.hasActiveConnection {
                    Button(bridge.isDisconnecting ? "Disconnecting…" : "Disconnect", systemImage: "xmark.circle", action: bridge.disconnect)
                        .disabled(bridge.isDisconnecting)
                } else {
                    Button("Scan Nearby", systemImage: "dot.radiowaves.left.and.right", action: bridge.scan)
                        .disabled(bridge.isStartingScan)
                }
            }

            if !bridge.devices.isEmpty && bridge.report == nil {
                Section("Nearby Devices") {
                    ForEach(bridge.devices) { device in
                        Button {
                            bridge.connect(to: device.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(device.detail)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(bridge.hasActiveConnection || !device.isConnectable)
                    }
                }
            }

            if bridge.report != nil {
                Section("Read-Only Vehicle Scan") {
                    if let scanStatus = bridge.liveScanStatus {
                        Text(scanStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        ShareLink(item: bridge.status + "\n" + scanStatus, subject: Text("FIXD connection status")) {
                            Label("Share Connection Status", systemImage: "square.and.arrow.up")
                        }
                    }
                    if bridge.canStopLiveReadings {
                        Button(
                            bridge.isStopRequested ? "Stopping Live Readings…" : "Stop Live Readings",
                            systemImage: "stop.circle",
                            action: bridge.stopVehicleReadings
                        )
                        .disabled(bridge.isStopRequested)
                    } else if bridge.canStartLiveScan {
                        Button("Scan Vehicle", systemImage: "stethoscope", action: bridge.startLiveScan)
                        Button("Start Live Readings", systemImage: "waveform.path", action: bridge.startMonitoring)
                        Text("With the vehicle parked and ignition on, start a scan or stream supported readings to the Dashboard and Signals tabs.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let snapshot = bridge.liveScanResult {
                FIXDScanResultView(snapshot: snapshot)
            }

            if let report = bridge.report {
                Section("Discovery Report") {
                    Text(report.name)
                        .font(.headline)
                    Text(report.source.uuidString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    ShareLink(item: report.text, subject: Text("Bluetooth discovery report")) {
                        Label("Share Discovery Report", systemImage: "square.and.arrow.up")
                    }
                }

                ForEach(report.apkMatches) { profile in
                    Section("Android APK Profile") {
                        Text("APK profile match · hardware session unverified")
                            .font(.subheadline.weight(.medium))
                        Text(profile.summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(report.services) { service in
                    Section {
                        if let issue = service.issue {
                            Text(issue)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if let message = service.emptyResultMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(service.characteristics ?? []) { characteristic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(characteristic.uuid)
                                    .font(.subheadline.monospaced())
                                    .textSelection(.enabled)
                                Text(characteristic.properties.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.isPrimary ? "Primary Service" : "Secondary Service")
                            Text(service.uuid)
                                .font(.caption.monospaced())
                        }
                        .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bluetooth Inspector")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NearbyDevice: Identifiable {
    let id: UUID
    let name: String
    let signal: Int?
    let isConnectable: Bool

    var detail: String {
        var parts = [String(id.uuidString.prefix(8))]
        if let signal {
            parts.append("\(signal) dBm")
        }
        if !isConnectable {
            parts.append("Not connectable")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ServiceSnapshot: Identifiable {
    let id: ObjectIdentifier
    let uuid: String
    let isPrimary: Bool
    var issue: String?
    var characteristics: [CharacteristicSnapshot]?

    var emptyResultMessage: String? {
        guard let characteristics else { return "Characteristic results are unavailable." }
        return characteristics.isEmpty ? "No characteristics returned." : nil
    }
}

private struct CharacteristicSnapshot: Identifiable {
    let id: ObjectIdentifier
    let uuid: String
    let flags: CBCharacteristicProperties
    let properties: [String]

    init(_ characteristic: CBCharacteristic) {
        let names: [(CBCharacteristicProperties, String)] = [
            (.broadcast, "Broadcast"),
            (.read, "Read"),
            (.writeWithoutResponse, "Write without response"),
            (.write, "Write"),
            (.notify, "Notify"),
            (.indicate, "Indicate"),
            (.authenticatedSignedWrites, "Authenticated signed writes"),
            (.extendedProperties, "Extended properties"),
            (.notifyEncryptionRequired, "Notification requires encryption"),
            (.indicateEncryptionRequired, "Indication requires encryption")
        ]
        id = ObjectIdentifier(characteristic)
        uuid = characteristic.uuid.uuidString
        flags = characteristic.properties
        let descriptions = names.compactMap { characteristic.properties.contains($0.0) ? $0.1 : nil }
        properties = descriptions.isEmpty ? ["No properties reported"] : descriptions
    }
}

private struct APKProfile: Identifiable {
    static let observed = [
        Self(service: "18F0", receive: "2AF0", transmit: "2AF1"),
        Self(service: "FFF0", receive: "FFF1", transmit: "FFF2")
    ]

    let service: String
    let receive: String
    let transmit: String

    var id: String { service }
    var summary: String { "\(service) service · \(receive) notify · \(transmit) write" }

    func matches(_ snapshot: ServiceSnapshot) -> Bool {
        guard Self.shortID(snapshot.uuid) == service,
              let characteristics = snapshot.characteristics
        else { return false }

        let receives = characteristics.contains {
            Self.shortID($0.uuid) == receive && !$0.flags.intersection([.notify, .indicate]).isEmpty
        }
        let transmits = characteristics.contains {
            Self.shortID($0.uuid) == transmit && !$0.flags.intersection([.write, .writeWithoutResponse]).isEmpty
        }
        return receives && transmits
    }

    func liveEndpoints(in gattService: CBService) -> FIXDEndpoints? {
        guard Self.shortID(gattService.uuid.uuidString) == service,
              let characteristics = gattService.characteristics else { return nil }
        let receiveCandidates = characteristics.filter {
            Self.shortID($0.uuid.uuidString) == receive && !$0.properties.intersection([.notify, .indicate]).isEmpty
        }
        let transmitCandidates = characteristics.filter {
            Self.shortID($0.uuid.uuidString) == transmit && !$0.properties.intersection([.write, .writeWithoutResponse]).isEmpty
        }
        guard receiveCandidates.count == 1, transmitCandidates.count == 1 else { return nil }
        return FIXDEndpoints(receive: receiveCandidates[0], transmit: transmitCandidates[0])
    }

    private static func shortID(_ uuid: String) -> String {
        let upper = uuid.uppercased()
        if upper.count == 36, upper.hasPrefix("0000"), upper.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            return String(upper.dropFirst(4).prefix(4))
        }
        if upper.count == 8, upper.hasPrefix("0000") {
            return String(upper.suffix(4))
        }
        return upper
    }
}

private struct FIXDEndpoints {
    let receive: CBCharacteristic
    let transmit: CBCharacteristic
}

private struct DiscoveryReport {
    let source: UUID
    let name: String
    let discoveredAt: Date
    var outcome: String
    var services: [ServiceSnapshot] = []

    var apkMatches: [APKProfile] {
        APKProfile.observed.filter { profile in services.contains(where: profile.matches) }
    }

    var text: String {
        var lines = [
            "Bluetooth Discovery Report",
            "Scope: GATT discovery only",
            "Device: \(name)",
            "iOS peripheral identifier: \(source.uuidString)",
            "Started: \(discoveredAt.ISO8601Format())",
            "Discovery result: \(outcome)"
        ]
        for profile in apkMatches {
            lines += ["", "APK profile match · hardware session unverified", "  \(profile.summary)"]
        }
        for service in services {
            let role = service.isPrimary ? "primary" : "secondary"
            lines += ["", "Service \(service.uuid) (\(role))"]
            if let issue = service.issue ?? service.emptyResultMessage {
                lines.append("  \(issue)")
            }
            for characteristic in service.characteristics ?? [] {
                lines.append("  \(characteristic.uuid) — \(characteristic.properties.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class BluetoothBridge: NSObject, ObservableObject {
    let vehicle = VehicleTelemetry()
    private enum Phase: Equatable {
        case idle, startingScan, scanning, connecting, discovering, ready, disconnecting
    }

    @Published private(set) var status = "Ready to scan for nearby peripherals."
    @Published fileprivate var devices: [NearbyDevice] = []
    @Published fileprivate var report: DiscoveryReport?
    @Published private(set) var liveScanStatus: String?
    @Published private(set) var liveScanResult: FIXDScanSnapshot?
    private enum ScanMode {
        case snapshot, continuous
    }

    @Published private var scanMode: ScanMode?
    @Published private(set) var isStopRequested = false
    @Published private var phase: Phase = .idle

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var pendingServices: Set<ObjectIdentifier> = []
    private var deadline: Task<Void, Never>?
    private var disconnectMessage = "Disconnected."
    private var liveSession: FIXDLiveSession?
    private var diagnosticConnection: FIXDReadScan.Connection?
    private var liveScanTask: Task<Void, Never>?

    private var isLiveScanRunning: Bool { scanMode != nil }
    var canStopLiveReadings: Bool {
        scanMode == .continuous && diagnosticConnection != nil
    }

    var isStartingScan: Bool { phase == .startingScan }
    var isScanning: Bool { phase == .scanning }
    var isDisconnecting: Bool { phase == .disconnecting }
    var hasActiveConnection: Bool {
        phase == .connecting || phase == .discovering || phase == .ready || phase == .disconnecting
    }

    var canStartLiveScan: Bool {
        phase == .ready && !isLiveScanRunning && candidateEndpoints != nil
    }

    private var candidateEndpoints: FIXDEndpoints? {
        guard let selected, selected.state == .connected,
              let name = report?.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              ["FIXD", "FIXD2"].contains(name) else { return nil }
        let endpoints = (selected.services ?? []).flatMap { service in
            APKProfile.observed.compactMap { $0.liveEndpoints(in: service) }
        }
        guard endpoints.count == 1 else { return nil }
        return endpoints[0]
    }

    func startLiveScan() {
        startScan(mode: .snapshot)
    }

    func startMonitoring() {
        startScan(mode: .continuous)
    }

    func stopVehicleReadings() {
        guard canStopLiveReadings, !isStopRequested else { return }
        isStopRequested = true
        vehicle.setMonitoring(false)
        liveScanStatus = "Stopping after the current adapter reply…"
    }

    private func startScan(mode: ScanMode) {
        guard canStartLiveScan, let selected, let endpoints = candidateEndpoints else { return }
        let session: FIXDLiveSession
        if let existing = liveSession {
            guard !existing.isInvalidated else {
                disconnect(because: "The diagnostic session expired. Reconnect to scan again.")
                return
            }
            session = existing
        } else {
            do {
                session = try FIXDLiveSession(peripheral: selected, receive: endpoints.receive, transmit: endpoints.transmit)
            } catch {
                liveScanStatus = error.localizedDescription
                return
            }
            liveSession = session
        }
        isStopRequested = false
        scanMode = mode
        liveScanStatus = "Preparing vehicle readings…"
        liveScanTask = Task { @MainActor [weak self] in
            await self?.readVehicle(using: session, mode: mode)
        }
    }

    private func readVehicle(using session: FIXDLiveSession, mode: ScanMode) async {
        guard liveSession === session, !Task.isCancelled else { return }
        do {
            let connection: FIXDReadScan.Connection
            if let verified = diagnosticConnection {
                connection = verified
            } else {
                connection = try await FIXDReadScan.connect(using: session) { message in
                    guard liveSession === session, !Task.isCancelled, !isStopRequested else { return }
                    liveScanStatus = message
                }
                guard liveSession === session, !Task.isCancelled else { return }
                diagnosticConnection = connection
                vehicle.markResponders(connection.responders)
            }

            let message: String
            switch mode {
            case .continuous:
                message = try await poll(using: session, connection: connection)
            case .snapshot:
                liveScanStatus = "Reading supported vehicle data…"
                let frame = try await FIXDReadScan.readCurrentData(using: session, connection: connection)
                guard liveSession === session, !Task.isCancelled else { return }
                publish(frame, connection: connection)
                liveScanStatus = "Reading stored, pending, and permanent trouble codes…"
                let codes = try await FIXDReadScan.readTroubleCodes(using: session)
                guard liveSession === session, !Task.isCancelled else { return }
                vehicle.recordTroubleCodes(codes)
                liveScanResult = Self.snapshot(frame, connection: connection, troubleCodes: codes)
                message = "Read-only scan complete. You can start live readings."
            }

            guard liveSession === session, !Task.isCancelled else { return }
            finishLiveScan(message)
        } catch {
            guard liveSession === session, !Task.isCancelled else { return }
            if session.isInvalidated {
                disconnect(because: "Diagnostic transport closed. " + error.localizedDescription)
            } else if isStopRequested {
                finishLiveScan("Live readings stopped.")
            } else {
                finishLiveScan("Vehicle readings stopped. " + error.localizedDescription)
            }
        }
    }

    private func poll(using session: FIXDLiveSession, connection: FIXDReadScan.Connection) async throws -> String {
        var emptyFrames = 0
        while !isStopRequested {
            if emptyFrames > 0 {
                liveScanStatus = "Waiting for live vehicle replies…"
            } else if !vehicle.isMonitoring {
                liveScanStatus = "Reading supported vehicle data…"
            }
            let frame = try await FIXDReadScan.readCurrentData(using: session, connection: connection) {
                !isStopRequested
            }
            guard liveSession === session, !Task.isCancelled, !isStopRequested else { break }

            if frame.readings.isEmpty {
                emptyFrames += 1
                vehicle.setMonitoring(false)
                if emptyFrames == 3 {
                    return "The vehicle returned no live values after three attempts."
                }
            } else {
                emptyFrames = 0
                publish(frame, connection: connection)
                vehicle.setMonitoring(true)
                liveScanStatus = "Live readings active in Dashboard and Signals."
            }
            try await Task.sleep(for: .seconds(2))
        }
        return "Live readings stopped."
    }

    private func publish(_ frame: FIXDReadScan.CurrentDataFrame, connection: FIXDReadScan.Connection) {
        vehicle.record(readings: frame.readings, capturedAt: frame.capturedAt)
        liveScanResult = Self.snapshot(frame, connection: connection, troubleCodes: [])
    }

    private static func snapshot(
        _ frame: FIXDReadScan.CurrentDataFrame,
        connection: FIXDReadScan.Connection,
        troubleCodes: [FIXDScanSnapshot.TroubleCodes]
    ) -> FIXDScanSnapshot {
        FIXDScanSnapshot(
            capturedAt: frame.capturedAt,
            vehicleProtocol: connection.vehicleProtocol,
            responders: connection.responders,
            readings: frame.readings,
            troubleCodes: troubleCodes,
            unavailableReadings: frame.unavailableReadings
        )
    }

    private func finishLiveScan(_ message: String) {
        liveScanTask = nil
        scanMode = nil
        isStopRequested = false
        liveScanStatus = message
        vehicle.setMonitoring(false)
    }

    private func resetLiveSession(_ message: String) {
        let wasReading = isLiveScanRunning
        liveScanTask?.cancel()
        liveScanTask = nil
        scanMode = nil
        isStopRequested = false
        let session = liveSession
        liveSession = nil
        diagnosticConnection = nil
        vehicle.setMonitoring(false)
        if wasReading {
            liveScanStatus = "Vehicle readings stopped. " + message
        } else if phase == .ready {
            liveScanStatus = "Diagnostic session closed."
        }
        session?.invalidate()
    }

    func scan() {
        guard phase == .idle else { return }
        devices.removeAll()
        peripherals.removeAll()
        report = nil
        liveScanResult = nil
        liveScanStatus = nil
        phase = .startingScan
        status = "Waiting for Bluetooth…"
        setDeadline { bridge in
            bridge.finishScan("Bluetooth did not become ready. Try scanning again.")
        }

        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        if let central {
            updateRadio(central.state)
        }
    }

    func stopScan() {
        guard isScanning else { return }
        finishScan(devices.isEmpty ? "Scan stopped. No peripherals found." : "Select an adapter to inspect.")
    }

    func connect(to id: UUID) {
        guard phase == .idle || phase == .scanning,
              let central, central.state == .poweredOn,
              let peripheral = peripherals[id],
              let device = devices.first(where: { $0.id == id && $0.isConnectable })
        else { return }

        if isScanning {
            finishScan("Select an adapter to inspect.")
        }

        vehicle.clearForNewAdapter()
        selected = peripheral
        peripheral.delegate = self
        report = DiscoveryReport(
            source: id,
            name: device.name,
            discoveredAt: .now,
            outcome: "Connecting…"
        )
        phase = .connecting
        status = "Connecting to \(device.name)…"
        setDeadline { bridge in
            bridge.report?.outcome = "Connection timed out."
            bridge.disconnect(because: "Connection timed out.")
        }
        central.connect(peripheral)
    }

    func disconnect() {
        disconnect(because: "Disconnected.")
    }

    func close() {
        if isStartingScan || isScanning {
            finishScan("Scan stopped.")
        }
        if hasActiveConnection {
            disconnect(because: "Bluetooth closed when the app entered the background.")
        }
    }

    private func finishScan(_ message: String) {
        deadline?.cancel()
        if central?.isScanning == true {
            central?.stopScan()
        }
        phase = .idle
        status = message
    }

    private func disconnect(because message: String) {
        guard let peripheral = selected, !isDisconnecting else { return }
        resetLiveSession(message)
        deadline?.cancel()
        if phase == .connecting || phase == .discovering {
            report?.outcome = message == "Disconnected." ? "Discovery cancelled." : message
        }
        guard let central, central.state == .poweredOn, peripheral.state != .disconnected else {
            finishConnection(message)
            return
        }
        disconnectMessage = message
        phase = .disconnecting
        vehicle.setAdapterConnected(false)
        status = "Disconnecting…"
        central.cancelPeripheralConnection(peripheral)
    }

    private func finishConnection(_ message: String) {
        resetLiveSession(message)
        deadline?.cancel()
        selected?.delegate = nil
        selected = nil
        vehicle.setAdapterConnected(false)
        pendingServices.removeAll()
        phase = .idle
        status = message
    }

    private func finishDiscovery() {
        deadline?.cancel()
        let completed = report?.services.count ?? 0
        let errors = report?.services.filter { $0.issue != nil }.count ?? 0
        let result: String
        if completed == 0 {
            result = "No services returned."
        } else if errors > 0 {
            result = "Found \(completed) services. Characteristic discovery failed for \(errors)."
        } else {
            result = "Discovery complete. Found \(completed) services."
        }
        report?.outcome = result
        phase = .ready
        let matchedAdapter = candidateEndpoints != nil
        status = matchedAdapter ? "FIXD connected." : result
        vehicle.setAdapterConnected(matchedAdapter)
        liveScanStatus = matchedAdapter
            ? "Ready to scan or start live readings."
            : "Live scanning needs one complete FIXD or FIXD2 Bluetooth profile."
    }

    private func setDeadline(_ action: @escaping @MainActor (BluetoothBridge) -> Void) {
        deadline?.cancel()
        deadline = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(12))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            action(self)
        }
    }

    private func updateRadio(_ state: CBManagerState) {
        if state == .poweredOn {
            guard phase == .startingScan, let central else { return }
            phase = .scanning
            status = "Scanning nearby peripherals…"
            central.scanForPeripherals(withServices: nil, options: nil)
            setDeadline { bridge in
                bridge.finishScan(
                    bridge.devices.isEmpty ? "No peripherals found. You can scan again." : "Select an adapter to inspect."
                )
            }
            return
        }

        let message: String
        switch state {
        case .unknown: return
        case .resetting: message = "Bluetooth is resetting. Try again shortly."
        case .unsupported: message = "Bluetooth Low Energy is unavailable on this device."
        case .unauthorized: message = "Bluetooth access is unavailable. Check the app’s access in Settings."
        case .poweredOff: message = "Turn on Bluetooth to scan nearby."
        case .poweredOn: return
        @unknown default: message = "Bluetooth is unavailable."
        }

        if isStartingScan || isScanning {
            finishScan(message)
        } else if hasActiveConnection {
            if phase == .connecting || phase == .discovering {
                report?.outcome = message
            }
            finishConnection(message)
        } else {
            status = message
        }
    }
}

extension BluetoothBridge: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateRadio(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isScanning else { return }
        peripherals[peripheral.identifier] = peripheral
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = [localName, peripheral.name].compactMap { $0 }.first {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? "Unnamed peripheral"
        let saved = NearbyDevice(
            id: peripheral.identifier,
            name: name,
            signal: RSSI.intValue == 127 ? nil : RSSI.intValue,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
        )
        if let index = devices.firstIndex(where: { $0.id == saved.id }) {
            devices[index] = saved
        } else {
            devices.append(saved)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard selected === peripheral, phase == .connecting else { return }
        phase = .discovering
        status = "Discovering services and characteristic properties…"
        report?.outcome = "Discovery in progress."
        setDeadline { bridge in
            bridge.disconnect(because: "Discovery timed out. Partial results remain available.")
        }
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard selected === peripheral else { return }
        let message = isDisconnecting ? disconnectMessage : (error?.localizedDescription ?? "Connection failed.")
        if !isDisconnecting {
            report?.outcome = message
        }
        finishConnection(message)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard selected === peripheral else { return }
        let message = isDisconnecting ? disconnectMessage :
            (error.map { "Bluetooth connection lost. " + $0.localizedDescription } ?? "Bluetooth connection lost.")
        if phase == .connecting || phase == .discovering {
            report?.outcome = message
        }
        finishConnection(message)
    }
}

extension BluetoothBridge: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard selected === peripheral, !invalidatedServices.isEmpty else { return }
        disconnect(because: "Adapter services changed. Reconnect to scan again.")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard selected === peripheral else { return }
        liveSession?.didUpdateNotificationState(for: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard selected === peripheral else { return }
        liveSession?.didUpdateValue(for: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard selected === peripheral else { return }
        liveSession?.didWriteValue(for: characteristic, error: error)
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard selected === peripheral else { return }
        liveSession?.peripheralIsReadyToSendWriteWithoutResponse()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard selected === peripheral, phase == .discovering else { return }
        if let error {
            disconnect(because: "Service discovery failed. \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        pendingServices = Set(services.map { ObjectIdentifier($0) })
        report?.services = services.map {
            ServiceSnapshot(id: ObjectIdentifier($0), uuid: $0.uuid.uuidString, isPrimary: $0.isPrimary)
        }
        if services.isEmpty {
            finishDiscovery()
        } else {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard selected === peripheral, phase == .discovering else { return }
        let id = ObjectIdentifier(service)
        guard pendingServices.remove(id) != nil,
              let index = report?.services.firstIndex(where: { $0.id == id })
        else { return }

        if let error {
            report?.services[index].issue = "Characteristic discovery failed. \(error.localizedDescription)"
        } else {
            report?.services[index].characteristics = (service.characteristics ?? []).map(CharacteristicSnapshot.init)
        }

        if pendingServices.isEmpty {
            finishDiscovery()
        }
    }
}
