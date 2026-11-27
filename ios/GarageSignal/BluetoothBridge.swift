import CoreBluetooth
import Foundation
import SwiftUI

@MainActor
struct AdapterInspectorView: View {
    @StateObject private var bridge = BluetoothBridge()

    var body: some View {
        List {
            Section {
                Label("GATT discovery only", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Text("Discover the Bluetooth services and characteristic properties of an adapter you select. Discovery sends no diagnostic commands.")
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
        .onDisappear(perform: bridge.close)
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
            Self.shortID($0.uuid) == receive && $0.flags.contains(.notify)
        }
        let transmits = characteristics.contains {
            Self.shortID($0.uuid) == transmit && !$0.flags.intersection([.write, .writeWithoutResponse]).isEmpty
        }
        return receives && transmits
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
private final class BluetoothBridge: NSObject, ObservableObject {
    private enum Phase: Equatable {
        case idle, startingScan, scanning, connecting, discovering, ready, disconnecting
    }

    @Published private(set) var status = "Ready to scan for nearby peripherals."
    @Published private(set) var devices: [NearbyDevice] = []
    @Published private(set) var report: DiscoveryReport?
    @Published private var phase: Phase = .idle

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var pendingServices: Set<ObjectIdentifier> = []
    private var deadline: Task<Void, Never>?
    private var disconnectMessage = "Disconnected."

    var isStartingScan: Bool { phase == .startingScan }
    var isScanning: Bool { phase == .scanning }
    var isDisconnecting: Bool { phase == .disconnecting }
    var hasActiveConnection: Bool {
        phase == .connecting || phase == .discovering || phase == .ready || phase == .disconnecting
    }

    func scan() {
        guard phase == .idle else { return }
        devices.removeAll()
        peripherals.removeAll()
        report = nil
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
            disconnect()
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
        status = "Disconnecting…"
        central.cancelPeripheralConnection(peripheral)
    }

    private func finishConnection(_ message: String) {
        deadline?.cancel()
        selected?.delegate = nil
        selected = nil
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
        status = result
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
        let message = isDisconnecting ? disconnectMessage : (error?.localizedDescription ?? "Peripheral disconnected.")
        if phase == .connecting || phase == .discovering {
            report?.outcome = message
        }
        finishConnection(message)
    }
}

extension BluetoothBridge: @preconcurrency CBPeripheralDelegate {
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
