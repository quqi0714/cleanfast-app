import Foundation

struct FastingSession: Codable, Equatable {
    var startDate: Date
    var targetDuration: TimeInterval

    var targetEndDate: Date { startDate.addingTimeInterval(targetDuration) }
}
