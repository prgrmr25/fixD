/// The raw transmission distinction code in an identified Honda CANEAT record.
public struct HondaAutomaticTransmission: Equatable, Sendable {
    public let distinctionCode: UInt8

    public static func identification(reply: String) -> HondaAutomaticTransmission? {
        guard let response = try? ELMResponseParser.parse(reply, for: .hondaData(.transmission)).first,
              case .manufacturerData(let body) = response.outcome,
              body.count == 36 else { return nil }
        return HondaAutomaticTransmission(distinctionCode: body[9])
    }
}

/// Measured values in the Honda CANEAT 2201 transmission data list.
public struct HondaTransmissionReadings: Equatable, Sendable {
    public let atfCelsius: Int
    public let engineRPM: Int
    public let inputRPM: Int
    public let outputRPM: Int

    /// Decodes the data body after the transport has validated the responder and DID.
    public static func decode(body: [UInt8]) -> HondaTransmissionReadings? {
        guard body.count == 36 else { return nil }

        func rpm(at offset: Int) -> Int {
            (Int(body[offset]) << 8) | Int(body[offset + 1])
        }

        return HondaTransmissionReadings(
            atfCelsius: Int(body[26]) - 40,
            engineRPM: rpm(at: 7),
            inputRPM: rpm(at: 11),
            outputRPM: rpm(at: 9)
        )
    }
}
