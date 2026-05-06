import SwiftUI

struct ContentView: View {
    @StateObject private var vm = FastingTimerViewModel()
    @State private var needsOnboarding: Bool = !PersistenceService.shared.hasCompletedOnboarding
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        ZStack {
            if needsOnboarding {
                OnboardingView(vm: vm) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        needsOnboarding = false
                    }
                }
                .transition(.opacity)
            } else {
                HomeView(vm: vm)
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettingsStore())
}
