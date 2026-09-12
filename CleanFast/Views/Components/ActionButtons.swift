import SwiftUI

struct PrimaryButton: View {
    var title: String
    var color: Color = AppColor.sunOrange
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: color.opacity(0.25), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppColor.cardSurface.opacity(0.7), in: shape)
                .overlay(
                    shape
                        .stroke(AppColor.restGraySoft, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
