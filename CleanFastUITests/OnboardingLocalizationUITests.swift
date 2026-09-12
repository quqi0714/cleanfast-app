import XCTest

final class OnboardingLocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEnglishOnboardingAndSettingsLocalization() throws {
        runLocalization(
            language: "en",
            locale: "en_US",
            expected: .english
        )
    }

    @MainActor
    func testTraditionalChineseOnboardingAndSettingsLocalization() throws {
        runLocalization(
            language: "zh-Hant",
            locale: "zh_TW",
            expected: .traditionalChinese
        )
    }

    @MainActor
    private func runLocalization(language: String, locale: String, expected: ExpectedCopy) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-hasCompletedOnboarding.v1", "NO"
        ]
        app.launch()

        // PersistenceService reads the App Group suite. If it does not honor the
        // requested argument-domain reset, do not clear state or add a test-only
        // production switch; report the blocked run instead.
        guard requireVisible(
            app.staticTexts[expected.welcomeTitle].firstMatch,
            named: "onboarding welcome title"
        ) else {
            capture(app, name: "\(expected.id)-blocked-before-onboarding")
            XCTFail("The launch-argument reset did not expose the onboarding flow; App Group state was left unchanged.")
            return
        }
        capture(app, name: "\(expected.id)-onboarding-01-welcome")

        guard tapButton(expected.start, in: app, named: "onboarding start") else { return }
        guard requireVisible(
            app.staticTexts[expected.setupTitle].firstMatch,
            named: "onboarding setup title"
        ) else { return }
        capture(app, name: "\(expected.id)-onboarding-02-setup")

        app.swipeUp()
        guard requireVisible(
            app.staticTexts[expected.setupLastCardTitle].firstMatch,
            named: "onboarding setup final card"
        ) else { return }
        guard requireVisible(
            app.staticTexts[expected.setupLastCardBody].firstMatch,
            named: "onboarding setup final card body"
        ) else { return }
        capture(app, name: "\(expected.id)-onboarding-02-setup-bottom")

        guard tapButton(expected.next, in: app, named: "onboarding next after setup") else { return }
        guard requireVisible(
            app.staticTexts[expected.targetTitle].firstMatch,
            named: "onboarding target title"
        ) else { return }
        capture(app, name: "\(expected.id)-onboarding-03-target")

        guard tapButton(expected.next, in: app, named: "onboarding next after target") else { return }
        guard requireVisible(
            app.staticTexts[expected.timingTitle].firstMatch,
            named: "onboarding timing title"
        ) else { return }
        capture(app, name: "\(expected.id)-onboarding-04-timing")

        guard tapButton(expected.next, in: app, named: "onboarding next after timing") else { return }
        guard requireVisible(
            app.staticTexts[expected.homeStyleTitle].firstMatch,
            named: "onboarding home style title"
        ) else { return }
        capture(app, name: "\(expected.id)-onboarding-05-home-style")

        guard tapButton(expected.next, in: app, named: "onboarding next after home style") else { return }
        guard requireVisible(
            app.staticTexts[expected.widgetTitle].firstMatch,
            named: "onboarding widget title"
        ) else { return }
        capture(app, name: "\(expected.id)-onboarding-06-widget")

        guard tapButton(expected.continueButton, in: app, named: "onboarding continue") else { return }
        guard requireVisible(
            app.staticTexts[expected.notificationTitle].firstMatch,
            named: "onboarding notification title"
        ) else { return }
        capture(app, name: "\(expected.id)-onboarding-07-notifications")

        // Keep the test from requesting system notification permission.
        guard tapButton(expected.notNow, in: app, named: "onboarding not now") else { return }
        guard requireVisible(
            app.buttons[expected.settingsButton].firstMatch,
            named: "home settings button"
        ) else { return }

        guard tapButton(expected.settingsButton, in: app, named: "open settings") else { return }
        guard requireVisible(
            app.staticTexts[expected.settingsTitle].firstMatch,
            named: "settings title"
        ) else { return }

        let notificationToggle = app.switches[expected.notificationSwitch].firstMatch
        guard requireVisible(notificationToggle, named: "notifications switch after Not now") else { return }
        capture(app, name: "\(expected.id)-settings-notifications-off")
        guard requireSwitchOff(notificationToggle, named: "notifications switch after Not now") else { return }

        guard tapButton(expected.manual, in: app, named: "manual timing mode") else { return }
        guard requireVisible(
            app.staticTexts[expected.manualFooter].firstMatch,
            named: "manual timing footer"
        ) else { return }
        capture(app, name: "\(expected.id)-settings-manual")

        guard tapButton(expected.automatic, in: app, named: "automatic timing mode") else { return }
        guard requireVisible(
            app.staticTexts[expected.automaticFooter].firstMatch,
            named: "automatic timing footer"
        ) else { return }
        capture(app, name: "\(expected.id)-settings-automatic")

        guard scrollUntilVisible(
            app.staticTexts[expected.widgetSettingsTitle].firstMatch,
            in: app,
            named: "settings widget explanation"
        ) else { return }
        guard requireVisible(
            app.staticTexts[expected.widgetSettingsTitle].firstMatch,
            named: "settings widget explanation"
        ) else { return }
        for (index, instruction) in expected.widgetInstructions.enumerated() {
            let element = app.staticTexts[instruction].firstMatch
            guard scrollUntilVisible(
                element,
                in: app,
                named: "settings widget instruction \(index + 1)"
            ) else { return }
            guard requireVisible(
                element,
                named: "settings widget instruction \(index + 1)"
            ) else { return }
        }
        let lockScreenInstructions = app.staticTexts[expected.widgetLockScreen].firstMatch
        guard scrollUntilVisible(
            lockScreenInstructions,
            in: app,
            named: "settings widget lock screen instruction"
        ) else { return }
        guard requireVisible(
            lockScreenInstructions,
            named: "settings widget lock screen instruction"
        ) else { return }
        // SettingsView currently renders the four steps inline in the Widget row;
        // keep this screenshot as the reviewable details state.
        capture(app, name: "\(expected.id)-settings-widget-details")

        guard scrollUntilVisible(
            app.staticTexts[expected.ageHealthNotice].firstMatch,
            in: app,
            named: "settings age health notice"
        ) else { return }
        guard requireVisible(
            app.staticTexts[expected.ageHealthNotice].firstMatch,
            named: "settings age health notice"
        ) else { return }
        app.swipeUp()
        guard requireVisible(
            app.staticTexts[expected.ageHealthNotice].firstMatch,
            named: "settings age health notice after scroll"
        ) else { return }
        // A multiline string used as XCUIElementQuery's identifier can trigger
        // an XCTest assertion. Match the final sentence by accessibility label
        // and use the saved screenshot to review the complete paragraph.
        let medicalNotice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", expected.healthMedicalNoticeSuffix)
        ).firstMatch
        guard requireVisible(
            medicalNotice,
            named: "settings medical health notice"
        ) else { return }
        capture(app, name: "\(expected.id)-settings-health-18-plus")
    }

    @MainActor
    private func tapButton(_ title: String, in app: XCUIApplication, named name: String) -> Bool {
        let button = app.buttons[title].firstMatch
        guard requireVisible(button, named: name) else { return false }
        button.tap()
        return true
    }

    @MainActor
    private func requireVisible(_ element: XCUIElement, named name: String) -> Bool {
        guard element.waitForExistence(timeout: 12) else {
            XCTFail("Missing \(name): \(element.debugDescription)")
            return false
        }
        guard element.isHittable else {
            XCTFail("\(name) exists but is not visible/hittable")
            return false
        }
        return true
    }

    @MainActor
    private func requireSwitchOff(_ element: XCUIElement, named name: String) -> Bool {
        if let value = element.value as? String {
            guard value == "0" else {
                XCTFail("\(name) has value \(value), expected 0")
                return false
            }
            return true
        }
        if let value = element.value as? NSNumber {
            guard !value.boolValue else {
                XCTFail("\(name) is on, expected off")
                return false
            }
            return true
        }
        XCTFail("\(name) exposed an unexpected value: \(String(describing: element.value))")
        return false
    }

    @MainActor
    private func scrollUntilVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        named name: String
    ) -> Bool {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        XCTFail("Could not scroll to \(name)")
        return false
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension OnboardingLocalizationUITests {
    struct ExpectedCopy {
        let id: String
        let welcomeTitle: String
        let start: String
        let setupTitle: String
        let setupLastCardTitle: String
        let setupLastCardBody: String
        let next: String
        let targetTitle: String
        let timingTitle: String
        let homeStyleTitle: String
        let widgetTitle: String
        let continueButton: String
        let notificationTitle: String
        let notNow: String
        let settingsButton: String
        let settingsTitle: String
        let notificationSwitch: String
        let manual: String
        let manualFooter: String
        let automatic: String
        let automaticFooter: String
        let widgetSettingsTitle: String
        let widgetInstructions: [String]
        let widgetLockScreen: String
        let ageHealthNotice: String
        let healthMedicalNoticeSuffix: String

        static let english = ExpectedCopy(
            id: "en",
            welcomeTitle: "CleanFast",
            start: "Start",
            setupTitle: "A quick setup",
            setupLastCardTitle: "Need a day off?",
            setupLastCardBody: "Skip today anytime — come back tomorrow.",
            next: "Next",
            targetTitle: "Choose fasting length",
            timingTitle: "Choose switching mode",
            homeStyleTitle: "Choose home style",
            widgetTitle: "Put your progress on the Home Screen",
            continueButton: "Continue",
            notificationTitle: "Reminders when it matters",
            notNow: "Not now",
            settingsButton: "Settings",
            settingsTitle: "Settings",
            notificationSwitch: "Notify me when reached",
            manual: "Manual",
            manualFooter: "Reminds you when time is up — you choose when to switch.",
            automatic: "Automatic",
            automaticFooter: "Switches on schedule — open the app to see which window you're in.",
            widgetSettingsTitle: "Home & Lock Screen Widgets",
            widgetInstructions: [
                "Touch and hold an empty area on the Home Screen",
                "Tap “+” at the top left, or “Edit” → “Add Widget”",
                "Search “CleanFast”",
                "Choose a size, then tap “Add Widget”"
            ],
            widgetLockScreen: "Lock Screen: touch and hold → Customize → Add Widgets, then choose CleanFast.",
            ageHealthNotice: "CleanFast is intended for people aged 18 and over.",
            healthMedicalNoticeSuffix: "please consult a professional first."
        )

        static let traditionalChinese = ExpectedCopy(
            id: "zh-Hant",
            welcomeTitle: "輕斷食時鐘",
            start: "開始",
            setupTitle: "先簡單設定一下",
            setupLastCardTitle: "想休息一下？",
            setupLastCardBody: "可以隨時跳過今天。明天回來就好。",
            next: "下一步",
            targetTitle: "選擇斷食時長",
            timingTitle: "選擇切換方式",
            homeStyleTitle: "選擇首頁風格",
            widgetTitle: "把進度放到主畫面",
            continueButton: "繼續",
            notificationTitle: "需要時提醒你",
            notNow: "暫時不用",
            settingsButton: "設定",
            settingsTitle: "設定",
            notificationSwitch: "達成時提醒我",
            manual: "手動切換",
            manualFooter: "到點只提醒，什麼時候切換由你決定。",
            automatic: "自動切換",
            automaticFooter: "按時間自動切換，打開就知道現在是哪一段。",
            widgetSettingsTitle: "桌面 / 鎖定畫面小工具",
            widgetInstructions: [
                "長按主畫面空白處",
                "點選左上角「+」，或點「編輯」→「加入小工具」",
                "搜尋「輕斷食時鐘」",
                "選擇尺寸，然後點選「加入小工具」"
            ],
            widgetLockScreen: "鎖定畫面：長按鎖定畫面 → 自訂 → 加入小工具，選擇「輕斷食時鐘」。",
            ageHealthNotice: "本應用程式面向年滿 18 歲的人士。",
            healthMedicalNoticeSuffix: "請先諮詢專業人士。"
        )
    }
}
