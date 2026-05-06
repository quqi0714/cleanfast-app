import SwiftUI

/// 中文文本视图，对接保留旧的调用点。
/// 内部就是普通 SwiftUI Text + 一组样式参数——换行靠源字符串里的 `\n` 控制，
/// 不再尝试用 word joiner / pushOut 这类技巧（实测不可靠）。
struct ZHText: View {
    let content: String
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    var rounded: Bool = true
    var color: Color = AppColor.textSecondary
    var lineSpacing: CGFloat = 0
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(content)
            .font(.system(
                size: size,
                weight: weight,
                design: rounded ? .rounded : .default
            ))
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}
