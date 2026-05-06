import SwiftUI

/// 手动模式状态切换前弹出的"实际时间是几点"选择器入参。
enum ManualTimeAction: String, Identifiable {
    case startFasting
    case startEating
    case restartFasting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startFasting, .restartFasting:
            return "上顿饭结束时间"
        case .startEating:
            return "进食开始时间"
        }
    }

    var pickerLabel: String {
        switch self {
        case .startFasting, .restartFasting:
            return "上顿饭结束"
        case .startEating:
            return "进食开始"
        }
    }

    var confirmTitle: String {
        switch self {
        case .startFasting, .restartFasting:
            return "开始断食"
        case .startEating:
            return "开始进食"
        }
    }
}

/// 弹出 sheet：让用户选择"实际"开始/结束时间，然后 onConfirm 回调真正切换状态。
struct ManualTimePickerView: View {
    let action: ManualTimeAction
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: 18) {
            TimePickerSheetHeader(title: action.title) {
                Haptics.play(.cancel)
                dismiss()
            }

            RecentTimeWheelPicker(selection: $selectedDate)
                .frame(maxWidth: .infinity, alignment: .center)

            PrimaryButton(title: action.confirmTitle, color: AppColor.sunOrange) {
                Haptics.play(.primaryAdvance)
                onConfirm(clampedSelectedDate)
                dismiss()
            }
        }
        .padding(24)
        .background(AppColor.backgroundCream.ignoresSafeArea())
        .onAppear {
            selectedDate = clampedSelectedDate
        }
    }

    private var clampedSelectedDate: Date {
        RecentTimeSelection.clamp(selectedDate)
    }
}

/// 三段独立 wheel picker：日期 / 小时 / 分钟，限制在过去 48 小时内。
struct RecentTimeWheelPicker: View {
    @Binding var selection: Date

    @State private var referenceNow = Date()
    @State private var selectedDay: RecentDay = .today
    @State private var selectedHour: Int = 0
    @State private var selectedMinute: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            Picker("日期", selection: $selectedDay) {
                ForEach(dayOptions) { day in
                    Text(day.title).tag(day)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("小时", selection: $selectedHour) {
                ForEach(hourOptions, id: \.self) { hour in
                    Text("\(hour)").tag(hour)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("分钟", selection: $selectedMinute) {
                ForEach(minuteOptions, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 178)
        .onAppear {
            referenceNow = Date()
            applyState(from: RecentTimeSelection.clamp(selection, now: referenceNow))
        }
        .onChange(of: selectedDay) { _, _ in commitSelection() }
        .onChange(of: selectedHour) { _, _ in commitSelection() }
        .onChange(of: selectedMinute) { _, _ in commitSelection() }
    }

    private var dayOptions: [RecentDay] {
        let options = RecentTimeSelection.dayOptions(now: referenceNow)
        return options.isEmpty ? [.today] : options
    }

    private var hourOptions: [Int] {
        let day = dayOptions.contains(selectedDay) ? selectedDay : dayOptions.last ?? .today
        let options = RecentTimeSelection.hourOptions(day: day, now: referenceNow)
        return options.isEmpty ? Array(0..<24) : options
    }

    private var minuteOptions: [Int] {
        let day = dayOptions.contains(selectedDay) ? selectedDay : dayOptions.last ?? .today
        let hour = hourOptions.contains(selectedHour) ? selectedHour : hourOptions.last ?? 0
        let options = RecentTimeSelection.minuteOptions(day: day, hour: hour, now: referenceNow)
        return options.isEmpty ? Array(0..<60) : options
    }

    private func commitSelection() {
        let day = dayOptions.contains(selectedDay) ? selectedDay : dayOptions.last ?? .today
        let validHours = RecentTimeSelection.hourOptions(day: day, now: referenceNow)
        let hour = validHours.contains(selectedHour) ? selectedHour : validHours.last ?? 0
        let validMinutes = RecentTimeSelection.minuteOptions(day: day, hour: hour, now: referenceNow)
        let minute = validMinutes.contains(selectedMinute) ? selectedMinute : validMinutes.last ?? 0
        let candidate = RecentTimeSelection.date(day: day, hour: hour, minute: minute, now: referenceNow)
        let clamped = RecentTimeSelection.clamp(candidate, now: referenceNow)

        if selectedDay != day || selectedHour != hour || selectedMinute != minute {
            applyState(from: clamped)
        }
        selection = clamped
    }

    private func applyState(from date: Date) {
        let calendar = Calendar.current
        selectedDay = RecentTimeSelection.day(for: date, now: referenceNow)
        selectedHour = calendar.component(.hour, from: date)
        selectedMinute = calendar.component(.minute, from: date)
    }
}

/// 时间选择 sheet 的标题栏：居中标题 + 右上角"取消"按钮。
struct TimePickerSheetHeader: View {
    let title: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColor.cardSurface.opacity(0.55), in: Capsule())
            }
        }
        .frame(height: 44)
    }
}
