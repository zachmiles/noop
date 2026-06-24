import Foundation
import Combine
import CoreBluetooth
import WhoopStore

/// Local BLE source for RENPHO ES-CS20M / QN-series body scales.
///
/// The scale is episodic rather than a continuous wearable: NOOP listens for a paired scale waking up,
/// answers the QN-series handshake, then persists the final stable measurement as body metricSeries
/// rows. It intentionally runs on its own CoreBluetooth central so it can coexist with the active WHOOP
/// or HR strap path.
@MainActor
public final class RenphoScaleSource: NSObject, ObservableObject {

    public struct DiscoveredScale: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let rssi: Int
    }

    public enum Sex: Int {
        case male = 0
        case female = 1
    }

    public struct Profile {
        public let sex: Sex
        public let age: Int
        public let heightM: Double
        public let athlete: Bool
        public let algorithm: Int

        public init(sex: Sex, age: Int, heightM: Double, athlete: Bool = false, algorithm: Int = 0x04) {
            self.sex = sex
            self.age = age
            self.heightM = heightM
            self.athlete = athlete
            self.algorithm = algorithm
        }
    }

    public struct Reading: Equatable, Sendable {
        public let day: String
        public let measuredAt: Date
        public let weightKg: Double
        public let bodyFatPct: Double?
        public let resistance1: Int?
        public let resistance2: Int?
        public let metrics: [String: Double]
    }

    @Published public private(set) var discovered: [DiscoveredScale] = []
    @Published public private(set) var scanning = false
    @Published public private(set) var latest: Reading?
    @Published public private(set) var batteryPct: Int?

    private static let notifyChar = CBUUID(string: "FFF1")
    private static let commandChar = CBUUID(string: "FFF2")
    private static let qnScaleService = CBUUID(string: "FFE0")
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let firmwareRevision = CBUUID(string: "2A26")

    private static let epochOffset = 946_656_000
    private static let defaultVendorByte: UInt8 = 0xFF
    private static let guestUserId: UInt8 = 0xFE
    private static let kilogramUnitByte: UInt8 = 0x01
    private static let poundUnitByte: UInt8 = 0x02

    private let displayUnitByteProvider: () -> UInt8
    private let profileProvider: () -> Profile?
    private let deviceIdForPeripheral: (UUID) -> String?
    private let persist: (String, Reading) -> Void
    private let log: (String) -> Void
    private let discoveryOnly: Bool

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var pendingConnectID: UUID?
    private var seenPeripherals: [UUID: CBPeripheral] = [:]
    private var commandCharacteristic: CBCharacteristic?
    private var commandWriteType: CBCharacteristicWriteType = .withResponse
    private var writeCharacteristics: [String: (characteristic: CBCharacteristic, writeType: CBCharacteristicWriteType)] = [:]
    private var measurementCharacteristicIDs: Set<String> = []
    private var notifyReady = false
    private var handshakeStarted = false
    private var vendorByte = RenphoScaleSource.defaultVendorByte
    private var stateMask = 0
    private var resolverSent = false

    private let stateUnitSet = 1 << 0
    private let stateMeasurementInit = 1 << 1
    private let stateProfile = 1 << 2
    private let stateBasicFinal = 1 << 3

    public init(displayUnitByteProvider: (() -> UInt8)? = nil,
                profileProvider: @escaping () -> Profile? = { nil },
                deviceIdForPeripheral: @escaping (UUID) -> String? = { _ in nil },
                persist: @escaping (String, Reading) -> Void = { _, _ in },
                log: @escaping (String) -> Void = { _ in },
                discoveryOnly: Bool = false) {
        self.displayUnitByteProvider = displayUnitByteProvider ?? { RenphoScaleSource.defaultDisplayUnitByte() }
        self.profileProvider = profileProvider
        self.deviceIdForPeripheral = deviceIdForPeripheral
        self.persist = persist
        self.log = log
        self.discoveryOnly = discoveryOnly
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil)
    }

    public func scan() {
        discovered.removeAll()
        seenPeripherals.removeAll()
        scanning = true
        log("RENPHO scale: scanning for ES-CS20M / QN-series scales")
        guard central.state == .poweredOn else {
            log("RENPHO scale: Bluetooth not powered on (state=\(central.state.rawValue))")
            return
        }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func connect(_ id: UUID) {
        stopScan()
        let p = seenPeripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let p else {
            pendingConnectID = id
            log("RENPHO scale: scale \(id) not cached yet; scanning to find it")
            scan()
            return
        }
        seenPeripherals[id] = p
        peripheral = p
        p.delegate = self
        guard central.state == .poweredOn else {
            pendingConnectID = id
            log("RENPHO scale: Bluetooth not powered on; connect deferred")
            return
        }
        resetSession()
        log("RENPHO scale: connecting to \(id)")
        central.connect(p, options: nil)
    }

    public func stopScan() {
        scanning = false
        if central.state == .poweredOn { central.stopScan() }
    }

    public func stop() {
        stopScan()
        pendingConnectID = nil
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        commandCharacteristic = nil
        commandWriteType = .withResponse
        writeCharacteristics.removeAll()
        measurementCharacteristicIDs.removeAll()
        resetSession()
    }

    private func resetSession() {
        vendorByte = Self.defaultVendorByte
        stateMask = 0
        resolverSent = false
        notifyReady = false
        handshakeStarted = false
    }

    private func shouldShow(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if !discoveryOnly, deviceIdForPeripheral(peripheral.identifier) != nil { return true }
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (advName ?? peripheral.name ?? "").lowercased()
        return name.contains("renpho")
            || name.contains("es-cs20")
            || name.contains("escs20")
            || name.contains("es-32")
            || name.contains("qn-scale")
            || name.contains("qn scale")
            || name.contains("elis")
    }

    private func displayName(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name
        return (name?.isEmpty == false) ? name! : "RENPHO Scale"
    }

    private func updateVendorByte(from payload: Data, opcode: UInt8) {
        guard payload.count >= 3,
              [0x10, 0x12, 0x14, 0x21].contains(opcode) else { return }
        vendorByte = payload[2]
    }

    private func handle(payload: Data, name: String, id: UUID) {
        guard payload.count >= 2 else { return }
        let opcode = payload[0]
        let length = payload[1]
        log("RENPHO scale: notify opcode=0x\(hex(opcode)) len=\(Int(length)) bytes=\(hex(payload))")
        updateVendorByte(from: payload, opcode: opcode)

        switch (opcode, length) {
        case (0x12, _):
            writeOnce(mask: stateUnitSet, command: buildUnitCommand())
        case (0x14, _):
            writeOnce(mask: stateMeasurementInit, command: buildMeasurementInitCommand())
        case (0x21, 0x05):
            sendProfileIfNeeded()
        case (0x21, _):
            stateMask |= stateProfile
        case (0x10, 0x0E):
            handleExtendedMeasurement(payload, name: name, id: id)
        case (0x10, 0x0B):
            handleBasicMeasurement(payload, name: name, id: id)
        default:
            break
        }
    }

    private func writeOnce(mask: Int, command: Data) {
        guard stateMask & mask == 0 else { return }
        stateMask |= mask
        write(command)
    }

    private func startHandshakeIfReady() {
        guard !handshakeStarted, notifyReady, hasCommandTarget else { return }
        handshakeStarted = true
        log("RENPHO scale: measurement listener ready; waiting for scale requests")
    }

    private func sendProfileIfNeeded() {
        guard stateMask & stateProfile == 0 else { return }
        stateMask |= stateProfile
        let command: Data
        if let profile = profileProvider() {
            command = buildProfileCommand(profile)
            log("RENPHO scale: sending profile for body composition")
        } else {
            command = buildBootstrapProfileCommand()
            log("RENPHO scale: no binary-sex profile available; using weight-only bootstrap profile")
        }
        write(command)
    }

    private func handleExtendedMeasurement(_ payload: Data, name: String, id: UUID) {
        guard payload.count >= 14 else { return }
        let status = payload[4]
        let weight = Double(UInt16(payload[5]) << 8 | UInt16(payload[6])) / 100.0
        log("RENPHO scale: extended measurement status=\(Int(status)) weight=\(String(format: "%.1f", weight)) kg")
        if status == 1, !resolverSent, profileProvider() != nil {
            resolverSent = true
            write(buildProfileCommand(profileProvider()!))
            return
        }
        guard status == 2 else {
            log("RENPHO scale: waiting for final extended measurement")
            return
        }

        let rawBodyFat = UInt16(payload[11]) << 8 | UInt16(payload[12])
        let bodyFat = rawBodyFat == 0 ? nil : Double(rawBodyFat) / 10.0
        let r1 = Int(UInt16(payload[7]) << 8 | UInt16(payload[8]))
        let r2 = Int(UInt16(payload[9]) << 8 | UInt16(payload[10]))
        finishMeasurement(weightKg: weight,
                          bodyFatPct: bodyFat,
                          resistance1: r1 == 0 ? nil : r1,
                          resistance2: r2 == 0 ? nil : r2,
                          name: name,
                          id: id)
    }

    private func handleBasicMeasurement(_ payload: Data, name: String, id: UUID) {
        guard payload.count >= 11 else { return }
        let status = payload[5]
        log("RENPHO scale: basic measurement status=\(Int(status))")
        guard status == 0x01 else {
            log("RENPHO scale: waiting for final basic measurement")
            return
        }
        guard stateMask & stateBasicFinal == 0 else { return }
        stateMask |= stateBasicFinal

        let weight = Double(UInt16(payload[3]) << 8 | UInt16(payload[4])) / 100.0
        let r1 = Int(UInt16(payload[6]) << 8 | UInt16(payload[7]))
        let r2 = Int(UInt16(payload[8]) << 8 | UInt16(payload[9]))
        let resistance = r1 > 0 ? r1 : r2
        let bodyFat = profileProvider().flatMap { profile in
            resistance > 0 ? Self.calculateBodyFat(weightKg: weight, profile: profile, resistance: resistance) : nil
        }
        finishMeasurement(weightKg: weight,
                          bodyFatPct: bodyFat,
                          resistance1: r1 == 0 ? nil : r1,
                          resistance2: r2 == 0 ? nil : r2,
                          name: name,
                          id: id)
    }

    private func finishMeasurement(weightKg: Double,
                                   bodyFatPct: Double?,
                                   resistance1: Int?,
                                   resistance2: Int?,
                                   name: String,
                                   id: UUID) {
        write(buildEndMeasurementCommand())
        var metrics: [String: Double] = ["weight": round1(weightKg)]
        if let profile = profileProvider(), profile.heightM > 0 {
            metrics["bmi"] = round1(weightKg / (profile.heightM * profile.heightM))
        }
        if let bodyFatPct {
            metrics["body_fat"] = round1(bodyFatPct)
            if let profile = profileProvider() {
                metrics.merge(Self.derivedMetrics(weightKg: weightKg, bodyFatPct: bodyFatPct, profile: profile)) { _, new in new }
            }
        }
        let measuredAt = Date()
        let reading = Reading(day: Repository.localDayKey(measuredAt),
                              measuredAt: measuredAt,
                              weightKg: round1(weightKg),
                              bodyFatPct: bodyFatPct.map(round1),
                              resistance1: resistance1,
                              resistance2: resistance2,
                              metrics: metrics)
        latest = reading
        log("RENPHO scale: final reading from \(name): \(String(format: "%.1f", weightKg)) kg, metrics=\(metricSummary(metrics))")
        guard let deviceId = deviceIdForPeripheral(id) else {
            log("RENPHO scale: final reading did not match a paired scale peripheral \(id); not saved")
            return
        }
        log("RENPHO scale: persisting final reading for paired device \(deviceId)")
        persist(deviceId, reading)
    }

    private func write(_ data: Data) {
        guard let peripheral else {
            log("RENPHO scale: peripheral unavailable for command write")
            return
        }
        let targets = commandTargets(for: data)
        guard !targets.isEmpty else {
            log("RENPHO scale: command characteristic unavailable")
            return
        }
        for target in targets {
            log("RENPHO scale: writing command \(hex(data)) to \(target.characteristic.uuid) type=\(target.writeType == .withResponse ? "withResponse" : "withoutResponse")")
            peripheral.writeValue(data, for: target.characteristic, type: target.writeType)
        }
    }

    private var hasCommandTarget: Bool {
        commandCharacteristic != nil || !writeCharacteristics.isEmpty
    }

    private func commandTargets(for data: Data) -> [(characteristic: CBCharacteristic, writeType: CBCharacteristicWriteType)] {
        if let shared = writeCharacteristics[Self.commandChar.uuidString] {
            return [shared]
        }
        if let config = writeCharacteristics["FFE3"] {
            return [config]
        }
        if let commandCharacteristic {
            return [(commandCharacteristic, commandWriteType)]
        }
        return []
    }

    private func buildUnitCommand() -> Data {
        var payload = [UInt8](repeating: 0, count: 9)
        payload[0] = 0x13; payload[1] = 0x09; payload[2] = vendorByte
        payload[3] = displayUnitByteProvider(); payload[4] = 0x10
        payload[8] = checksum(payload[0..<8])
        log("RENPHO scale: setting display unit to \(payload[3] == Self.poundUnitByte ? "lb" : "kg")")
        return Data(payload)
    }

    private func buildMeasurementInitCommand() -> Data {
        var payload = [UInt8](repeating: 0, count: 8)
        payload[0] = 0x20; payload[1] = 0x08; payload[2] = vendorByte
        let ts = UInt32(max(0, Int(Date().timeIntervalSince1970) - Self.epochOffset))
        payload[3] = UInt8(ts & 0xFF)
        payload[4] = UInt8((ts >> 8) & 0xFF)
        payload[5] = UInt8((ts >> 16) & 0xFF)
        payload[6] = UInt8((ts >> 24) & 0xFF)
        payload[7] = checksum(payload[0..<7])
        return Data(payload)
    }

    private func buildEndMeasurementCommand() -> Data {
        var payload: [UInt8] = [0x1F, 0x05, vendorByte, 0x10, 0x00]
        payload[4] = checksum(payload[0..<4])
        return Data(payload)
    }

    private func buildBootstrapProfileCommand() -> Data {
        buildProfileCommand(Profile(sex: .male, age: 0, heightM: 0, algorithm: 0x00))
    }

    private func buildProfileCommand(_ profile: Profile) -> Data {
        let heightMm = max(0, min(65_535, Int((profile.heightM * 1000.0).rounded())))
        let flag = UInt8((profile.algorithm + (profile.athlete ? 0x0A : 0)) & 0xFF)
        var payload: [UInt8] = [
            0xA0, 0x0D, 0x02,
            Self.guestUserId, 0xFF, 0xEE,
            UInt8(profile.sex.rawValue & 0xFF),
            UInt8(max(0, min(120, profile.age))),
            UInt8((heightMm >> 8) & 0xFF),
            UInt8(heightMm & 0xFF),
            flag, 0x02, 0x00,
        ]
        payload[12] = checksum(payload[0..<12])
        return Data(payload)
    }

    private func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }

    private func round1(_ value: Double) -> Double {
        (value * 10.0).rounded() / 10.0
    }

    private func metricSummary(_ metrics: [String: Double]) -> String {
        metrics.keys.sorted().map { key in
            let value = metrics[key] ?? 0
            return "\(key)=\(String(format: "%.1f", value))"
        }
        .joined(separator: ", ")
    }

    private func hex(_ byte: UInt8) -> String {
        String(format: "%02X", byte)
    }

    private func hex(_ data: Data) -> String {
        data.map { hex($0) }.joined(separator: " ")
    }

    nonisolated private static func defaultDisplayUnitByte() -> UInt8 {
        let raw = UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? UnitSystem.metric.rawValue
        return UnitSystem(rawValue: raw) == .imperial ? poundUnitByte : kilogramUnitByte
    }
}

extension RenphoScaleSource: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("RENPHO scale: Bluetooth state changed to \(central.state.rawValue)")
        if central.state == .poweredOn {
            if let id = pendingConnectID, let p = seenPeripherals[id] {
                pendingConnectID = nil
                central.connect(p, options: nil)
            } else if scanning {
                central.scanForPeripherals(withServices: nil,
                                           options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        guard shouldShow(peripheral, advertisementData: advertisementData) else { return }
        let id = peripheral.identifier
        let firstSight = seenPeripherals[id] == nil
        seenPeripherals[id] = peripheral
        let name = displayName(for: peripheral, advertisementData: advertisementData)
        if firstSight { log("RENPHO scale: found \(name) (\(id)) rssi \(RSSI.intValue)") }
        let scale = DiscoveredScale(id: id, name: name, rssi: RSSI.intValue)
        if let idx = discovered.firstIndex(where: { $0.id == id }) {
            discovered[idx] = scale
        } else {
            discovered.append(scale)
        }
        if !discoveryOnly, deviceIdForPeripheral(id) != nil {
            connect(id)
        } else if pendingConnectID == id {
            pendingConnectID = nil
            connect(id)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("RENPHO scale: connected to \(peripheral.identifier); discovering services")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        log("RENPHO scale: failed to connect to \(peripheral.identifier): \(error?.localizedDescription ?? "unknown error")")
        if !discoveryOnly { scan() }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("RENPHO scale: disconnected from \(peripheral.identifier): \(error?.localizedDescription ?? "normal")")
        self.peripheral = nil
        commandCharacteristic = nil
        commandWriteType = .withResponse
        writeCharacteristics.removeAll()
        measurementCharacteristicIDs.removeAll()
        resetSession()
        if !discoveryOnly { scan() }
    }
}

extension RenphoScaleSource: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log("RENPHO scale: service discovery failed: \(error.localizedDescription)")
            return
        }
        log("RENPHO scale: discovered \(peripheral.services?.count ?? 0) services")
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        if let error {
            log("RENPHO scale: characteristic discovery failed for \(service.uuid): \(error.localizedDescription)")
            return
        }
        log("RENPHO scale: service \(service.uuid) has \(service.characteristics?.count ?? 0) characteristics")
        for characteristic in service.characteristics ?? [] {
            log("RENPHO scale: characteristic \(characteristic.uuid) properties=\(propertySummary(characteristic.properties))")
            let isCommand = characteristic.uuid == Self.commandChar
                || (service.uuid == Self.qnScaleService
                    && (characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)))
            let isNotify = characteristic.uuid == Self.notifyChar
                || (service.uuid == Self.qnScaleService
                    && (characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)))

            if isCommand {
                let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
                writeCharacteristics[characteristic.uuid.uuidString] = (characteristic, writeType)
                if commandCharacteristic == nil {
                    commandCharacteristic = characteristic
                    commandWriteType = writeType
                    log("RENPHO scale: command characteristic ready (\(characteristic.uuid))")
                } else {
                    log("RENPHO scale: additional command characteristic ready (\(characteristic.uuid))")
                }
            }
            if isNotify {
                measurementCharacteristicIDs.insert(characteristic.uuid.uuidString)
                peripheral.setNotifyValue(true, for: characteristic)
                notifyReady = true
                log("RENPHO scale: notification characteristic subscribed (\(characteristic.uuid))")
            }
            if characteristic.uuid == Self.batteryLevel {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.uuid == Self.firmwareRevision {
                peripheral.readValue(for: characteristic)
            }
        }
        startHandshakeIfReady()
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error {
            log("RENPHO scale: update failed for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        if characteristic.uuid == Self.notifyChar || measurementCharacteristicIDs.contains(characteristic.uuid.uuidString) {
            handle(payload: data, name: peripheral.name ?? "RENPHO Scale", id: peripheral.identifier)
        } else if characteristic.uuid == Self.batteryLevel, let pct = data.first {
            batteryPct = Int(pct)
            log("RENPHO scale: battery \(Int(pct))%")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error {
            log("RENPHO scale: notification state failed for \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            log("RENPHO scale: notification state \(characteristic.isNotifying ? "on" : "off") for \(characteristic.uuid)")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error {
            log("RENPHO scale: write failed for \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            log("RENPHO scale: write acknowledged for \(characteristic.uuid)")
        }
    }

    private func propertySummary(_ properties: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if properties.contains(.read) { parts.append("read") }
        if properties.contains(.write) { parts.append("write") }
        if properties.contains(.writeWithoutResponse) { parts.append("writeWithoutResponse") }
        if properties.contains(.notify) { parts.append("notify") }
        if properties.contains(.indicate) { parts.append("indicate") }
        return parts.isEmpty ? "none" : parts.joined(separator: "|")
    }
}

private extension RenphoScaleSource {
    static func derivedMetrics(weightKg: Double, bodyFatPct: Double, profile: Profile) -> [String: Double] {
        let sexIndex = profile.sex == .male ? 0 : 1
        let fatFreeMass = clamp(round2(weightKg * (100.0 - bodyFatPct) / 100.0), min: 5, max: 200)
        let bodyWater = clamp(round1([72.202, 68.651][sexIndex] + [-0.72223, -0.68725][sexIndex] * bodyFatPct),
                              min: 20, max: 80)
        let skeletalMuscle = clamp(round1([64.713, 58.390][sexIndex] + [-0.65508, -0.58654][sexIndex] * bodyFatPct),
                                   min: 17.5, max: 70)
        let softLeanPct = round1([94.992, 93.988][sexIndex] + [-0.94969, -0.93960][sexIndex] * bodyFatPct)
        let softLeanKg = clamp(round2(weightKg * softLeanPct / 100.0), min: 3.75, max: 110)
        let fatKg = bodyFatPct * weightKg / 100.0
        let boneMass = clamp(round2(weightKg - softLeanKg - fatKg), min: 1, max: 7)
        let muscleMass = round2(weightKg - boneMass - fatKg)
        let protein = clamp(round1([22.787, 25.340][sexIndex] + [-0.22735, -0.30245][sexIndex] * bodyFatPct),
                            min: 5, max: 24)
        let bmr = clamp(round0([372.7023, 370.5818][sexIndex] + [430.9015, 359.6167][sexIndex] * boneMass),
                        min: 900, max: 2500)
        return [
            "lean_mass": fatFreeMass,
            "body_water": bodyWater,
            "skeletal_muscle": skeletalMuscle,
            "bone_mass": boneMass,
            "muscle_mass": muscleMass,
            "protein": protein,
            "bmr": bmr,
        ]
    }

    static func calculateBodyFat(weightKg: Double, profile: Profile, resistance: Int) -> Double? {
        guard weightKg > 0, profile.heightM > 0, resistance > 0 else { return nil }
        let bmi = weightKg / (profile.heightM * profile.heightM)
        let age = Double(profile.age)
        if profile.algorithm == 0x04 {
            let coeffs: (Double, Double, Double)
            switch (profile.sex, profile.athlete) {
            case (.male, false): coeffs = (1.524, 0.103, -21.992)
            case (.female, false): coeffs = (1.545, 0.097, -12.689)
            case (.male, true): coeffs = (0.7678, 0.0292, -6.5417)
            case (.female, true): coeffs = (0.9310, 0.0326, -4.5527)
            }
            var bf = coeffs.0 * bmi + coeffs.1 * age + coeffs.2
            if !profile.athlete { bf -= 500.0 / Double(resistance) }
            return round1(bf)
        }
        return nil
    }

    static func round0(_ value: Double) -> Double { value.rounded() }
    static func round1(_ value: Double) -> Double { (value * 10.0).rounded() / 10.0 }
    static func round2(_ value: Double) -> Double { (value * 100.0).rounded() / 100.0 }
    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}
