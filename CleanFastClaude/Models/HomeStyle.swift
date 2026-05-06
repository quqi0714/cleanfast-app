import Foundation

enum HomeStyle: String, Codable, CaseIterable, Identifiable {
    case classic
    case cinematic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "经典"
        case .cinematic: return "极简"
        }
    }
}
