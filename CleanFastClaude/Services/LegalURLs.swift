import Foundation

/// 法律 / 联系方式相关的外链常量。运营主体：MaxHope LLC。
///
/// 法律页面目前托管在 GitHub Pages（已验证在线）；
/// 日后若迁到 maxhope.la 域名，只需改 `base` 一处。
enum LegalURLs {
    /// 法律页面域名前缀。
    private static let base = "https://quqi0714.github.io/cleanfast"

    static let privacyPolicy = URL(string: "\(base)/privacy.html")!
    static let termsOfUse    = URL(string: "\(base)/terms.html")!

    static let contactEmail = "app@maxhope.la"
    static let mailto = URL(string: "mailto:\(contactEmail)?subject=CleanFast%20%E5%8F%8D%E9%A6%88")!

    /// 应用版本号 + 构建号，从 Info.plist 读取（避免硬编码）。
    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
