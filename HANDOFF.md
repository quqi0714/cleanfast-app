# HANDOFF.md — 当前交接状态

最新核验：2026-09-11。长期约定见 AGENTS.md。以本快照和当前代码为准。

## 当前项目与发布候选

- 当前源码目录：`/Users/qu/Desktop/APP/CleanFast-App`。
- 工程：`CleanFast.xcodeproj`；主 Scheme、target、module、产品名：`CleanFast`。
- 扩展：`CleanFastWidgetExtension`；Widget kind：`CleanFastWidget`。
- 测试：`CleanFastTests` / `CleanFastUITests`。
- 候选版本：**1.0 (5)**；Xcode 27 RC 27A266a；iOS 27 RC 模拟器 24A434。
- 公司 Team：57H8BQUP62 / MaxHope LLC。主 ID `com.MaxQ.CleanFast`，Widget ID `com.MaxQ.CleanFast.CleanFastWidget`，App Group `group.la.maxhope.cleanfast`。
- 图标不更换；主图 SHA256 `1e4f5c5b4bda760188599e8440caf1519819db63f889cdad2e3432285b63a5e5`。
- 未删除或重装用户手机 App；本次未修改手机断食记录。Widget kind 已改成正式名，旧开发版已添加的小组件在更新后可能需要重新添加。

## 本轮完成与验证

1. 统一工程、目录、target、测试、Swift 类型、Widget kind 和归档命名；当前仓库（排除 Git 历史）及最终归档的文件名、普通文本、二进制 ASCII/UTF-16 字符串扫描均无旧开发命名。清理了 Finder/Xcode 的旧路径缓存；两个过期归档已移出 Organizer，保留历史备份。
2. 修复启动时系统通知删除可能同步等待 XPC 的问题：主线程立即失效旧通知计划，系统清理放到 utility 队列；删除与添加任务继续严格按顺序执行。新增 3 个确定性回归，覆盖启动时删除挂起、慢删除与新计划竞争、删除过程中取消。
3. **49/49 单测通过**，0 failures、0 skipped、0 runtime warnings。最终源码无新增编译警告。结果：`/Users/qu/Documents/New project/cleanfast-release-2026-09-11/final-tests.xcresult`。
4. 最终公司签名 Release Archive 成功：`/Users/qu/Documents/New project/cleanfast-release-2026-09-11/archive/CleanFast-Final-1.0-5.xcarchive`。主 App/Widget 签名验证通过，真实签名 Team/App Group 正确；归档名称 CleanFast。完整扫描：同目录上级 `final-name-audit.json`。
5. 实际模拟器启动已恢复并采得最终英文主屏。早先机器同时运行多个模拟器和编译导致高负载；已改为顺序验证。不得把纯白截图作为界面验收证据。
6. F08 自动周期追赶移除 200 次循环上限，按完整周期直接计算，App/Widget 保持镜像；覆盖跨年、多周期、极短周期、无效时长及独立迭代参考算法。跨多周期不虚增达标次数。
7. F03 设置说明补充自动提醒仅预排未来 6 次；F04 自动模式等待恢复显示时间及提前开始；F05 深色进食页降低背景强度与光晕、增加遮罩、主按钮改深色文字；F06 小屏采用滚动布局及缩小圆环。最终 F04 恢复提示、F05 深色进食页、F06 SE 默认字号布局已截图并由主线程目检通过；SE 主按钮已实际点击并成功显示休息确认。结果见 `cleanfast-release-2026-09-11/final-ui-review.json`。
8. 通知异步修复后的最终英文/繁体七步引导与设置 UI 测试 **2/2 通过**，分别61.723秒和60.305秒，0 failures。截图证据位于 `cleanfast-release-2026-09-11/ui-fixes`。

## 商店后台与宣传材料

- App Store Connect Apple ID 6810958220，SKU cleanfast-001，版本仍准备提交。
- 简体、英文、繁体名称、副标题、关键词、推广文字、已批准的长描述、支持 URL、隐私 URL 已保存并切换语言读回验证。基本 ASO 已配置；未声称搜索量、关键词排名或转化率已验证。
- 版权 2026 MaxHope LLC；无第三方内容；审核无需登录；英文审核说明已保存。
- App Privacy 已发布为 No Data Collected；Mac 与 Vision Pro 分发已取消，保持 iPhone-only。
- 18+ 定位已统一商店分级、App 三语言说明、官网中英文协议/隐私政策；不增加年龄确认或数据收集。官网 `https://quqi0714.github.io/cleanfast/` 与隐私页在线可访问，内容含中英文。
- 描述首句突出 16:8 断食计时器。手动默认推荐，自动适合固定作息；一次买断，无订阅、无广告、无内购；禁止竞品比较、宗教词汇与减肥疗效承诺。
- 12 张三语言 1320×2868 商店图已从最终构建重新采集、排版检查并打包。最终 ZIP 只含 12 张不透明 RGB PNG 与验收清单。当天晚间登录恢复后，三语言12张已上传到6.9英寸栏（6.5英寸自动继承），刷新后逐语言读回确认；顺序统一为断食计时、两种界面、进食、休息。旧 Build 3 图保存在独立历史备份。路径 `/Users/qu/Documents/New project/cleanfast-store-2026-09-11`。
- 最新后台证据：`/Users/qu/Documents/New project/cleanfast-release-2026-09-11/metadata/ASC-STATUS.json`；文案见 `AppStore/store-copy.md`。

## 仍待完成 / 需要所有者的信息

- 最终截图及 F04/F05/F06 布局、英文/繁体 UI 流程已验收；SE 主按钮已实际点击并成功显示休息确认。三语言截图已上传并读回确认。
- 最终苹果 Validate 已通过；1.0 (5) 已成功上传到 App Store Connect，Xcode 显示 CleanFast 1.0 (5) uploaded。晚间网页登录恢复，后台构建已处理完成，已选择 1.0 (5) 并保存到待提交版本。未提交 App Review。
- 所有者已确认美国基准价 $1.99 一次买断、其他首发地区自动换算；首批美国、加拿大、英国、澳大利亚、新西兰、新加坡、香港、澳门、台湾。欧盟同步准备 DSA；中国大陆核实离线应用备案要求后再决定开放，目标价 ¥6。九个首发地区已在后台保存并读回“App 发布时供应”；不自动扩展新地区。价格仍未配置，遵守收款/税务环节暂停。审核联系人姓名、电话、邮箱已按所有者提供的信息保存，刷新页面后已目检确认；私人电话不写入仓库。
- 首发收费与限免讨论：当前建议保持收费、促销码仅用于体验反馈；未授权限免日期或改价。官方机制核实及英文编辑推荐申请草稿已写入 `/Users/qu/Documents/New project/cleanfast-release-2026-09-11/metadata/launch-strategy.md`，尚未提交提名，发布日期待定。
- **收款/税务设置未完成，W-9 环节暂停，等待 Apple 工单回复和所有者明确通知。** 具体税务身份、表单问题及沟通细节保留在本地发布记录，不纳入源码仓库。
- **不得代交 W-9、修改法律实体或银行收款资料，不得把收款/税务配置标为完成；涉及该环节及依赖其完成的操作均等待所有者通知。** 不依赖此问题的上架准备可继续。此前 Paid Apps Agreement 未签署是历史观察；用户现已自行处理资料，当前协议/银行状态未复核，不据旧记录推断。
- 手机已从原安装版原位覆盖到 **1.0 (5)**（最终归档内的开发签名App，系统严格签名校验通过，devicectl安装成功）。未卸载、重置或主动修改记录。启动请求因手机锁屏被拒绝，iPhone镜像需要Touch ID/Mac密码，已询问所有者；当次启动和画面检查未完成；所有者随后取消本轮重复真机验收，不再作为上架等待条件。
- 真实系统通知送达仍未完成真机验收；仅有逻辑回归与模拟器启动验证，不可写为全部通知实测完成。
- 所有者已授权将当前发布候选纳入 Git 并推送至 `origin/main`；同步状态以实际本地 HEAD 与远端提交核对为准，禁止强制推送或覆盖他人更新。

## W-9 等待期间新增准备

- 后台九个首发地区已保存；英文审核备注新增操作步骤及手动/自动模式到点行为区别，保存后刷新读回。类别、18+、非医疗设备、未收集数据标签已复核；官网/隐私/条款均HTTP200，中英文及18+说明存在。
- 当前50个源码文件与最终清单全部匹配。旧手动导出日志不代表最终上传结果：Organizer GUI验证上传成功且商店已处理构建5。本地归档保留Development签名用于设备验收；沙箱信任服务报错已由系统权限下codesign严格验证通过排除。
- 推荐文案已压缩至后台1000字符限制内，但保存前强制要求发布日期；未虚构日期或提交提名。辅助功能标签未作未验证声明。
- 集中清单：`/Users/qu/Documents/New project/cleanfast-release-2026-09-11/metadata/release-readiness.md`。收款/税务、价格配置和最终提交批准仍待完成；不能称W-9解决后立即自动上线。

## 所有者最新验收范围调整

所有者明确要求本轮不再重复小组件等真机验证（已多次做过）。取消该项及镜像解锁作为上架准备等待条件，不再索取解锁；保留此前安装成功/启动因锁屏未验证的客观记录，不将取消重测记作新测试通过。

兼容性已按实际1.0(5)归档复核：主App和Widget最低iOS17.0，设备族iPhone，SDK iOS27.0；本轮完整测试基线iOS27RC，未逐版实测所有旧系统。iPad无专用适配；Mac/Vision Pro商店分发关闭。

## Mac 开发副本清理与 GitHub 核对

所有者授权清理Mac搜索重复项后，删除10个明确的可重建Build缓存目录（20个App/测试Runner副本，约467MiB），并取消27条已定位开发/归档程序的LaunchServices登记。系统登记剩一个手机应用占位入口；未删除该系统入口。源码50/50散列未变；最终归档、xcresult、截图保留。细项见发布目录 `metadata/mac-search-cleanup.json`。旧文档中的Build/Products路径可能已不存在，需要时重新构建；不得因此判定源码或发布归档遗失。没有全局重置索引；搜索界面刷新未能通过工具目检。

本次同步前，GitHub `origin/main` 为 `a0fa88fe2b7a1ba06df65d4cd158189f8c0292d8`（2026-08-05）。所有者随后明确要求推送当前上线候选。本提交包含工程更名、已验证的功能修复、测试、本地化与商店交接文档；不包含开发缓存、安装包或私人税务资料。

## 后续版本约定

此次首发为1.0；纯BUG修复递增为1.0.1、1.0.2等，新增功能为1.1、1.2等，大版本为2.0等。内部构建号独立递增，当前仍为5。详细长期约定见AGENTS.md；本次没有更改安装包版本。
