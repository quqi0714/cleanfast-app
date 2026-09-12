import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var appAppearance: AppAppearance {
        didSet {
            guard appAppearance != oldValue else { return }
            persistence.appAppearance = appAppearance
        }
    }

    @Published var homeStyle: HomeStyle {
        didSet {
            guard homeStyle != oldValue else { return }
            persistence.homeStyle = homeStyle
        }
    }

    private let persistence: PersistenceService

    init(persistence: PersistenceService = .shared) {
        self.persistence = persistence
        appAppearance = persistence.appAppearance
        homeStyle = persistence.homeStyle
    }

    func reload() {
        let persistedAppearance = persistence.appAppearance
        if appAppearance != persistedAppearance {
            appAppearance = persistedAppearance
        }

        let persistedHomeStyle = persistence.homeStyle
        if homeStyle != persistedHomeStyle {
            homeStyle = persistedHomeStyle
        }
    }
}
