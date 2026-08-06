# HANDOFF.md — 交接状态快照

> 快照日期：2026-07-25。长期约定见 `AGENTS.md`（先读它）。
> 本文件描述"进展到哪、下一步做什么"，做完一项请更新本文件。

## 一句话现状

代码与上架素材 100% 就绪（构建 ✓、34/34 测试 ✓、截图文案 ✓、法律页已上线 ✓），
正在走 Apple 组织开发者账号与公司行政流程，**当前总瓶颈：等 EIN**。

## 业务侧状态

| 事项 | 状态 |
|---|---|
| 公司主体 | MaxHope LLC（加州，2026-07-04 成立，File No. B20260309230，注册地址 2108 N ST STE N, Sacramento, CA 95816 = Northwest 注册代理地址） |
| D-U-N-S | ✅ 已取得 |
| Apple 组织开发者账号 | 待注册/注册中（developer.apple.com/enroll，选 Organization；$99 可用所有者个人卡付） |
| EIN | ⏳ 等待中——阻塞对公银行账户 |
| 对公银行账户 | 未开（EIN 到手后开，Mercury/Relay 对新 LLC 友好） |
| Paid Applications 协议 | 未签（需 EIN + 对公账户；付费 App 上架销售的前提） |
| 定价 | 建议首发 ¥6/$0.99（冲量攒评分后可调），**所有者尚未最终拍板** |
| 法律页 | ✅ https://quqi0714.github.io/cleanfast/ 三页已上线，主体 MaxHope LLC，邮箱 app@maxhope.la |
| 加州合规提醒 | 首份 Statement of Information 须在成立 90 天内（≈2026-10-02 前）提交——确认 Northwest 是否代报；每年 $800 franchise tax |

## 上线流水线（按序执行，当前在第 1 步）

1. **注册组织开发者账号**（D-U-N-S 已具备；身份页姓名必须与证件拼音一致
   Hengliang Qu；实体类型务必选 Organization 不要手滑选 Individual）
2. 账号批准后：Xcode 里把签名 Team 从 `545M7K6H6K`（个人免费 Team）切到
   MaxHope LLC 新 Team；开发者后台注册 Bundle ID `com.MaxQ.CleanFast` +
   App Group `group.com.MaxQ.CleanFast`
3. Archive → 上传 App Store Connect
4. Connect 建 App 记录，元数据**逐格照抄 `AppStore/store-copy.md`**
   （名称/副标题/关键词/描述/新版本说明，zh-Hans + en-US + zh-Hant，
   附加 es-MX / en-GB 集见同文件）；截图用 `AppStore/screenshots/zh-framed`
   与 `en-framed` 各 5 张（1320×2868）
5. TestFlight 真机自测数天
6. EIN 到手 → 开对公账户 → Connect 签 Paid Apps 协议 + 银行税务信息
7. 定价（见上）→ 隐私标签全选"不收集" → 年龄分级问卷 →
   **首发地区先不勾欧盟**（避免公司地址电话公示义务）→ 提交审核

## 代码侧状态

- main 分支即最新，全部已推送。构建通过；34/34 单测通过。
- 近期关键提交：`51080d4` 审计修复批（widget 时间线冻结/前天映射/通知系列等
  12 项）、`3290219` 主体切换、`5d8cf50` 本地化按钮修复、`cf5d794`+`6807e12`
  上架素材、`2b41e5d` 求评里程碑、`8d6a67e`→`14d0554` 文案 v3 定稿。
- 无已知 BUG。搁置项清单见 AGENTS.md 末节。

## 给接手代理的第一批任务建议

1. 读完 `AGENTS.md` + 本文件，跑一遍构建与测试确认环境
2. 陪所有者走完流水线第 1–5 步（Team 切换那步动 pbxproj 的
   DEVELOPMENT_TEAM，共 5 处，切完跑构建验证签名）
3. EIN 到位后走 6–7 步提交
4. 提交审核后若被打回：先对照 AGENTS.md 文案红线自查元数据，
   再看审核信具体条款

## 历史背景速览（为什么是现在这样）

- 曾评估个人主体 vs 公司主体，最终定公司（MaxHope LLC 已实际运营）
- 曾全面审查并修复：widget 自动模式时间线冻结、"前天"映射差一天、
  英文界面按钮未本地化等；此后又做过 8 角度 code-review 与全状态矩阵
  截图排查，均无正确性缺陷存留
- 文案经历三版演进：功能清单 → 反订阅宣言（因审核风险撤回比较性表述）→
  现行"有原则的计时器"正面自述版。**不要回退到比较性表述**
