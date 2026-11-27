/// Reference labels from the 2011 Acura MDX 3.7L factory code charts.
enum MDXTroubleCode {
    static func description(for code: String) -> String? {
        switch code {
        case "P0741": return "Torque converter clutch hydraulic circuit stuck off"
        case "P2646": return "VTEC rocker-arm oil pressure switch circuit voltage low"
        case "P2647": return "VTEC rocker-arm oil pressure switch circuit voltage high"
        case "P2648": return "VTEC rocker-arm oil control solenoid circuit voltage low"
        case "P2649": return "VTEC rocker-arm oil control solenoid circuit voltage high"
        default: return nil
        }
    }
}
