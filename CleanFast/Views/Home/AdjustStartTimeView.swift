import SwiftUI

/// 进行中会话的"忘记按了，把开始时间调一下"sheet。仅手动模式可用。
struct AdjustStartTimeView: View {
    @ObservedObject var vm: FastingTimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(vm: FastingTimerViewModel) {
        self.vm = vm
        _selectedDate = State(initialValue: RecentTimeSelection.clamp(vm.session?.startDate ?? Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TimePickerSheetHeader(title: String(localized: "调整开始时间")) {
                Haptics.play(.cancel)
                dismiss()
            }

            ZHText(content: "忘记点了？把开始时间调回实际时间就好。",
                   size: 14, color: AppColor.textSecondary, lineSpacing: 3)

            RecentTimeWheelPicker(selection: $selectedDate)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)

            PrimaryButton(title: String(localized: "应用"), color: AppColor.sunOrange) {
                vm.adjustCurrentSessionStartDate(clampedSelectedDate)
                Haptics.play(.adjustTime)
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
