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
