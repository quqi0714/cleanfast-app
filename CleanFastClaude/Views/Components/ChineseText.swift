import SwiftUI

/// 中文文本视图，对接保留旧的调用点。
/// 内部就是普通 SwiftUI Text + 一组样式参数——换行靠源字符串里的 `\n` 控制，
/// 不再尝试用 word joiner / pushOut 这类技巧（实测不可靠）。
struct ZHText: View {
    private let text: Text
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    var rounded: Bool = true
    var color: Color = AppColor.textSecondary
    var lineSpacing: CGFloat = 0
    var alignment: TextAlignment = .leading

    /// 主入口：接受 `LocalizedStringKey`。字面量调用会自动从 `Localizable.xcstrings` 查表。
    init(
        content: LocalizedStringKey,
        size: CGFloat = 14,
        weight: Font.Weight = .regular,
        rounded: Bool = true,
        color: Color = AppColor.textSecondary,
        lineSpacing: CGFloat = 0,
        alignment: TextAlignment = .leading
    ) {
        self.text = Text(content)
        self.size = size
        self.weight = weight
        self.rounded = rounded
        self.color = color
        self.lineSpacing = lineSpacing
        self.alignment = alignment
    }

    /// 已经本地化好的动态字符串（来自 model `String(localized:)` 等）—— 用 `Text(verbatim:)`
    /// 原样显示，避免 SwiftUI 把它当成 key 再查一次表。
    init(
        verbatim: String,
        size: CGFloat = 14,
        weight: Font.Weight = .regular,
        rounded: Bool = true,
        color: Color = AppColor.textSecondary,
        lineSpacing: CGFloat = 0,
        alignment: TextAlignment = .leading
    ) {
        self.text = Text(verbatim: verbatim)
        self.size = size
        self.weight = weight
        self.rounded = rounded
        self.color = color
        self.lineSpacing = lineSpacing
        self.alignment = alignment
    }

    var body: some View {
        text
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
