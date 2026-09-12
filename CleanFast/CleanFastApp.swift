//
//  CleanFastApp.swift
//  CleanFast
//
//  Created by Qu on 4/26/26.
//

import SwiftUI

@main
struct CleanFastApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettingsStore()

    init() {
        _ = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                // 唯一的外观应用入口。SwiftUI 自己会把 colorScheme 传播到所有
                // 子视图（包括 sheet / popover / fullScreenCover），不需要再额外
                // 调用 UIKit 的 overrideUserInterfaceStyle —— 那个会导致 trait
                // collection 同步广播，picker 选项被强制重渲染时视觉回弹。
                .preferredColorScheme(settings.appAppearance.colorScheme)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // 仅同步 UserDefaults 中可能被另一进程（如 widget）写入的变化。
                    // 不再调用 applyAppearance，避免回前台时 trait 强制刷新。
                    settings.reload()
                }
        }
    }
}
