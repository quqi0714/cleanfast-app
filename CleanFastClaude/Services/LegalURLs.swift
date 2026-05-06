import Foundation

/// 法律 / 联系方式相关的外链常量。
///
/// **注意**：上架前需把 `githubUserSlug` 改成你实际的 GitHub Pages 路径。
/// 现在用 `quqi0714` 占位（按你的 iCloud 邮箱 username 推测）；
/// 如果 GitHub 用户名不一样，把这里的字符串替换掉即可。
enum LegalURLs {
    /// GitHub Pages 域名前缀。形如 `https://<username>.github.io/<repo>`
    private static let base = "https://quqi0714.github.io/cleanfast"

    static let privacyPolicy = URL(string: "\(base)/privacy.html")!
    static let termsOfUse    = URL(string: "\(base)/terms.html")!

    static let contactEmail = "quqi0714@icloud.com"
    static let mailto = URL(string: "mailto:\(contactEmail)?subject=CleanFast%20%E5%8F%8D%E9%A6%88")!

    /// 应用版本号 + 构建号，从 Info.plist 读取（避免硬编码）。
    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
