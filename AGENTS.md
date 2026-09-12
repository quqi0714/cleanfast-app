# AGENTS.md — CleanFast 项目代理协作指南

> 本文件面向接手本仓库的 AI 编码代理。
> 时点性状态（业务进展、下一步）见 `HANDOFF.md`；本文件只放长期有效的约定。

## 项目是什么

CleanFast（轻断食时钟）：iOS 16:8 间歇性断食计时器。SwiftUI，iOS 17+，
Xcode 工程 `CleanFast.xcodeproj`，主 App target `CleanFast` +
Widget 扩展 `CleanFastWidgetExtension`。**iPhone-only、仅竖屏**（有意为之，勿改回）。

本仓库（`quqi0714/cleanfast-app`，**私有**）只放 App 源码。
法律页面（隐私政策/条款）在独立的**公开**仓库 `quqi0714/cleanfast`，
经 GitHub Pages 发布于 https://quqi0714.github.io/cleanfast/ ——
改法律文案去那个仓库，推 main 即发布；本仓库里没有它们的副本。

## 产品理念（最高准则，压倒一切功能建议）

适用人群：仅供年满 18 岁的人士使用。所有者于 2026-09-11 明确选择通过商店分级、协议和健康文案统一说明，不增加年龄确认步骤、年龄验证或年龄数据收集。

核心一个字：**轻**。低价一次买断。以下红线**永远不可触碰**：

- 不加订阅、不加内购、不加广告、不加"高级版"
- 不加账号系统、不联网、不接任何第三方 SDK / 分析 / 崩溃上报
- 不加打卡、连续天数、排行榜、勋章、社区、知识付费内容
- 通知克制：只在目标达成时发本地通知；任何新增打扰都要极其谨慎
- 求评弹窗仅限现有的第 3/10/30 次达标里程碑（所有者明确批准过，勿加频）

功能取舍时默认答案是"不加"。所有者做这个 App 的初衷就是要一个安静的闹钟。

## 文案红线（所有者明确要求，违反有真实后果）

1. **App Store 元数据只做正面自述**：绝不比较、不贬损其他应用、不出现
   "其他 App / 搜过 App Store / 别人都是订阅制"式表述（审核 2.3 风险，
   所有者非常在意账号安全）。"一次买断、无订阅无广告"是说自己——安全。
2. **词汇约束（所有者硬性要求）**：一切公开文案（商店、官网、社媒）避免
   宗教色彩词汇——"辟谷""过午不食"等一律不用，换中性生活用语。
3. 语气：温和、克制、不焦虑。健康表述必须带"通常/可能/逐渐"式限定词，
   绝不做医疗承诺或减肥疗效承诺。激烈用词（如"闭嘴"）不用，
   基调参考现有文案："默默陪伴，从不打扰"。

## 构建与测试

```bash
# 构建
xcodebuild build -project CleanFast.xcodeproj -scheme CleanFast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 单元测试（当前 49 个，提交前必须全绿）
xcodebuild test -project CleanFast.xcodeproj -scheme CleanFast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CleanFastTests
```

测试使用隔离的 UserDefaults suite（见 makeVM helper），可放心并行。

界面本地化回归使用 `-only-testing:CleanFastUITests/OnboardingLocalizationUITests -parallel-testing-enabled NO`，在专用测试模拟器上运行。两项测试分别覆盖英文、繁体七步引导与设置，重走引导并选择“暂时不用”，会修改该测试模拟器的引导/提醒设置；不用于用户手机。XCTAttachment保存完整流程截图，测试通过后仍需目检排版。

## 架构要点与不变量（改动前必读）

- **持久化**：App Group `group.la.maxhope.cleanfast` 的 UserDefaults，
  键名带版本后缀（如 `state.v1`），定义在 `PersistenceService.swift`。
  主 App 与 Widget 共享此存储。
- **⚠️ MIRROR 不变量**：`FastingTimerViewModel.advanceAutomaticCycle` 与
  `CleanFastWidget/WidgetData.swift` 的 `WidgetSnapshot.advanceAutomaticCycle`
  是**手工同步的镜像实现**（widget target 无法被测试 target 引用）。
  改一边必须同步另一边；App 侧行为由单测 `advanceAutomaticCycle_matchesPinnedReference` 钉住。
- **Widget 时间线策略**：`entries.count > 1 ? .atEnd : .never`。自动模式的
  跳过/待恢复路径必须包含恢复时刻 entry + 恢复后的密集 entry
  （曾因此出过"小组件冻结"BUG，勿回退）。
- **通知**：手动模式单条；自动模式预排最多 6 条系列
  （`NotificationService.scheduleSeries`，identifiers 见常量）。
  cancelAll 必须覆盖全部 identifier；系统通知删除操作不得阻塞主线程；提交/取消必须同步失效旧计划，并等待不可取消的旧 add 清理完才允许新计划写入。通知开关统一走 ViewModel.setNotificationsEnabled，旧授权回调不得恢复已关闭的提醒。
- **时间线倒挂钳制**：`startFasting`/`startEating` 会把开始时间钳制到
  不早于当前会话开始（生产期望行为；写测试时用 skipToday/resumeToday
  回到干净状态，不要绕过钳制）。
- **求评**：达标断食计数在 `recordCompletedFast`（手动结束达标 + 自动模式
  单周期实时切换；多周期追赶不计），里程碑 3/10/30。

## 本地化（历史上出过 2 个真 BUG 的雷区）

- 目录：主 App 与 Widget 各有 `Localizable.xcstrings`；源语言 zh-Hans，
  必须保持 en / zh-Hant 全覆盖。显示名在 `InfoPlist.xcstrings`（轻断食时钟/輕斷食時鐘/CleanFast）。
- **雷 1**：`PrimaryButton` / `SecondaryButton` / `TimePickerSheetHeader` 的
  title 参数是裸 `String`——传中文字面量必须包 `String(localized:)`，
  否则英文界面显示中文（曾整个 onboarding 中招）。新组件若加 String 参数，同理。
- **雷 2**：时间组合词条的英文语序是特调的（"%@ today" 而非 "today %@"，
  "Eat after %@"）——改英文翻译时先想想拼出来的完整句子。
- 验证方法：状态矩阵截图法（见 HANDOFF.md 提到的 shoot.py 思路：
  关机→写 App Group plist 种状态→开机→`simctl launch` 带
  `-AppleLanguages "(en)"` 截图逐张目检）。

## 当前签名与标识符

用户于 2026-09-10 明确废止此前 Bundle ID / App Group 永久不可改规则，授权公司团队签名调整。当前主 App Bundle ID 已成功注册到公司团队，予以保留。

- Team：`57H8BQUP62`（MaxHope LLC）
- Bundle ID：`com.MaxQ.CleanFast`
- Widget Bundle ID：`com.MaxQ.CleanFast.CleanFastWidget`
- App Group：`group.la.maxhope.cleanfast`
- App Group 必须在两个 `.entitlements`、`PersistenceService.appGroupIdentifier`、`WidgetSnapshot.appGroupIdentifier` 四处完全一致；修改后验收签名及真机 Widget 同步。
- 2026-09-10 公司签名切换时已按所有者决定完成无迁移的重新安装。此后更新采用覆盖安装，保留手机现有数据；不得沿用当时授权再次删除 App。
- 法律主体：MaxHope LLC（加州）；联系邮箱：app@maxhope.la
- 版权串：`© 2026 MaxHope LLC`（pbxproj 四处 + docs 页脚）

## 已知刻意不做 / 已评估搁置

启动屏背景色微调、文案硬 `\n` 断行、DST 漂移（自动模式纯间隔推进）、
自动模式的"调整锚点"入口、设置页两段式提交语义、5 个可选清理
（授权检查阶梯重复、钳制逻辑重复、双循环数学漂移风险、widget resume 快照
重建翻倍、tick/rehydrate 条件重复）——都有意留到 1.1+，别当成新发现的 BUG。

## 模拟器注意

iPhone 17 Pro / Pro Max 模拟器里可能残留手工种入的假断食会话
（通过直接改 App Group plist 注入）。删 App 重装即恢复干净。

## 工程命名

2026-09-11 所有者要求清理开发遗留命名。当前工程为 `CleanFast.xcodeproj`，主 Scheme/target/module 为 `CleanFast`，扩展为 `CleanFastWidgetExtension`，测试为 `CleanFastTests` / `CleanFastUITests`。归档与产物使用正式 CleanFast 名称。WidgetKit kind 统一为 `CleanFastWidget`；更新旧开发版后，已添加的小组件可能需要重新添加。Bundle ID、Team、App Group 与用户数据键不变。
