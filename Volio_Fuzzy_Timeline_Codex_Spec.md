# Volio iOS：锚点式模糊时间轴与批量归档实施文档

**文档用途**：直接交给 Codex，在当前 `boyang-workspace/volio` 仓库基础上实施。  
**目标版本**：Volio iOS 下一阶段 MVP  
**核心概念**：Anchored Fuzzy Timeline / 锚点式模糊时间轴  
**产品原则**：用户不需要记住准确日期，Volio 帮助用户在浏览中逐渐把散落的作品放回成长故事。

---

## 0. Codex 执行要求

请先完整阅读当前仓库，定位以下现有类型和调用链，再开始修改：

- `LocalWork`
- `VolioSession`
- `TimelineView`
- `CaptureView.swift`
- `StackCameraView`
- Photos Picker 导入流程
- Artwork detail / editor
- Mac 同步与 AI processing enqueue 流程
- 当前搜索实现

实施时遵守以下约束：

1. 在现有架构上增量修改，不进行无关的大规模重写。
2. 保留 local-first：原图必须先安全写入 iPhone 本地，任何后续操作失败都不能导致照片丢失。
3. **保留当前 iPhone 与 Mac 完全同步的产品逻辑。不要修改 Mac 删除后 iPhone 同步删除等镜像语义。**
4. 保留当前单孩子 MVP，不在本阶段引入复杂的多孩子账户体系。
5. AI 分析必须是后台增强能力，不能阻塞拍摄、保存、浏览或时间归档。
6. 不添加不必要的第三方依赖。
7. 保持当前 deployment target，不为了本功能抬高系统版本。
8. 优先做可维护的数据语义和稳定交互，不要只实现视觉 demo。
9. 每个阶段完成后运行现有测试和构建；补充本文要求的单元测试与 UI 测试。
10. 使用小步提交，建议按本文“实施顺序”拆分 commit。

---

# 1. 背景与问题

Volio 当前已经具备：

- iPhone 拍摄作品；
- 从系统相册批量选择；
- Gallery；
- Timeline；
- Search；
- 作品详情；
- Mac 同步；
- Mac AI 自动生成标题、描述、标签、材料、主题和颜色；
- 本地原图与缩略图保存。

当前最大的产品问题不是缺少更多 AI 功能，而是：

> 家长在补录旧作品时，通常无法回忆准确的创作日期，甚至无法确认年份。

如果系统继续把“拍摄日期”当作“作品创作日期”，历史作品会全部落入今天，Timeline 会失去可信度。

Volio 需要明确区分：

- **Captured At**：这张作品何时被数字化；
- **Created Around**：作品大约何时创作。

两者不能混用。

---

# 2. 产品目标

本阶段建立一个完整闭环：

```text
拍摄或导入
→ 原图立即安全保存
→ 批量选择模糊时间
→ 作品进入成长时间轴
→ 无法确认的作品散落在时间轴两侧
→ 用户浏览时偶然想起
→ 一键将作品放回附近阶段
```

最终体验不是“补全数据库字段”，而是：

> 在浏览孩子成长过程时，逐渐找回作品属于哪段时间。

---

# 3. 核心体验定义

## 3.1 中央时间轴

中间是已经定位或大致定位的作品，按照成长阶段排列，例如：

- 7 岁；
- 刚上一年级；
- 大约 5～6 岁；
- 幼儿园时期；
- 更早以前。

准确日期不是唯一组织方式。

## 3.2 两侧记忆碎片

尚未定位时间的作品，不集中放在一个“待处理列表”里，而是少量、零散、稳定地散落在当前时间轴内容的左右两侧。

视觉隐喻：

> 中间是已经整理好的成长故事，两边是还没有找到位置的记忆碎片。

这些作品必须：

- 尺寸小于正式时间轴作品；
- 左右随机分布；
- 有轻微旋转和偏移；
- 部分作品可以轻微贴近屏幕边缘；
- 同一次浏览过程中位置稳定；
- 下次或隔天浏览时可轮换为其他未定位作品；
- 不遮挡中央内容和重要按钮；
- 可点击，不依赖拖拽。

## 3.3 浏览中归位

用户点击侧边作品，展示极简归位卡：

```text
想起这是什么时候了吗？

[作品大图]

就是这段时间
比这更早
比这更晚
选择其他时间
还没想起来
```

其中“这段时间”指当前作品浮现在其附近的 Timeline section。

用户完成归位后：

1. 侧边小卡抬起；
2. 移向中央时间段；
3. 旋转归零；
4. 变为正式作品卡；
5. 显示短暂 Undo；
6. 数据持久化并参与同步。

---

# 4. 产品原则

## 4.1 不确定不是错误

不要使用以下表达：

- 时间缺失；
- 待修复；
- 未完成 83 项；
- 完成率；
- 红色警告；
- 置信度百分比。

使用自然语言：

- 大约 5～6 岁；
- 幼儿园时期；
- 还没想起来；
- 一些还没找到时间的作品；
- 这张属于这段时间吗？

## 4.2 不强迫准确

允许用户保存：

- 准确日期；
- 年月；
- 年份；
- 季节；
- 年龄；
- 年龄范围；
- 成长阶段；
- 大致在某个锚点之前或之后；
- 完全未知。

## 4.3 拍摄不能被整理阻塞

拍完后可以跳过归档。跳过的作品：

- 已安全保存在本地；
- 正常参与 AI 分析和同步；
- 可以在 Gallery 中找到；
- 会在 Timeline 两侧被温和地重新呈现；
- 不弹红点催促。

---

# 5. 本阶段范围

## P0：必须完成

1. 区分 `capturedAt` 与作品创作时间。
2. 修复拍摄和系统相册导入默认使用拍摄当天作为创作时间的问题。
3. 统一 Camera 与 Photos Picker 的批量归档流程。
4. 增加模糊时间数据模型。
5. 增加批量时间选择界面。
6. 增加作品详情页的时间编辑能力。
7. 改造 Timeline，支持中央 section 与两侧未定位作品。
8. 点击未定位作品，将其归入附近时间段。
9. 稳定随机布局与作品轮换机制。
10. 合并或幂等化 AI 分析触发，避免同一作品潜在的重复分析。
11. 保持 Mac 完全同步逻辑不变。
12. 添加数据迁移、单元测试和关键 UI 测试。

## P1：本阶段可预留接口，但不强制实现

- 手动时间锚点；
- “开始上小学”“第一次绘画课”等事件；
- 拖拽归位；
- AI 基于画风、纸张、材料和批次推荐可能阶段；
- 两张作品的“哪张更早”比较；
- 真正的向量语义搜索；
- 多孩子支持；
- 用户自定义阶段。

## 明确不做

- 通过 AI 武断预测准确日期；
- 复杂的置信度 UI；
- 自由 Canvas 式全页面绝对定位；
- 时间关系图谱；
- 一次展示所有未定位作品；
- 强制用户在拍摄后填写完整信息；
- 修改 Mac 全量镜像同步规则。

---

# 6. 信息架构

保留当前主要 Tab 结构，但调整其职责：

## Gallery

- 所有作品；
- 可保留一个轻量入口：“一些还没找到时间的作品”；
- 不显示强制待办数量或进度。

## Timeline

Timeline 是本功能的主要场景：

- 中央：已经定位的作品和阶段；
- 两侧：少量未定位作品；
- 点击侧边作品即可归位；
- 允许直接编辑某幅作品的时间。

## Search

本阶段不必实现真正向量搜索。当前搜索如果仍为字符串包含和规则扩展，不应继续对用户宣称为严格意义上的 Semantic Search。

建议：

- UI 使用 `Search` 或 `Smart Search`；
- 保留当前搜索能力；
- 真正 embedding search 放入后续版本。

## Add

Add 继续打开相机或照片选择器，但二者必须进入同一个 Capture Batch 流程。

---

# 7. 数据模型

## 7.1 不要推翻现有模型

当前模型已经包含部分 `createdAround` 能力。优先采用向后兼容的增量迁移，而不是一次性替换所有字段。

先检查现有：

- 创建日期；
- 年份；
- 季节；
- 年龄；
- unknown；
- creator；
- work type；
- sync status；
- AI status。

在此基础上补齐缺失语义。

## 7.2 建议枚举

```swift
enum CreationTimeKind: String, Codable, CaseIterable {
    case exactDate
    case yearMonth
    case season
    case year
    case age
    case ageRange
    case lifeStage
    case relative
    case unknown
}

enum TimeConfidence: String, Codable {
    case confirmed     // 用户明确确认
    case approximate   // 用户只记得大概
    case suggested     // 系统建议，尚未确认
    case unknown
}

enum TimelinePlacementState: String, Codable {
    case placed
    case approximate
    case unplaced
}

enum ReviewState: String, Codable {
    case pending
    case reviewed
}
```

## 7.3 `LocalWork` 建议新增或明确的字段

字段名可根据仓库现有命名调整，但语义必须存在。

```swift
var capturedAt: Date

var creationTimeKindRaw: String
var creationDateStart: Date?
var creationDateEnd: Date?

var creationYear: Int?
var creationMonth: Int?
var creationSeasonRaw: String?

var creationAgeStartMonths: Int?
var creationAgeEndMonths: Int?

var lifeStageID: String?
var customTimeLabel: String?

var timeConfidenceRaw: String
var timelinePlacementStateRaw: String
var reviewStateRaw: String

var timelineSortKey: Double?

var displaySeed: Int64
var lastSurfacedAt: Date?
var surfaceCount: Int
var snoozedUntil: Date?
```

如果现有字段已覆盖其中一部分，复用现有字段，不创建重复真相源。

## 7.4 关键语义

### `capturedAt`

作品被拍摄或从系统相册导入 Volio 的时间。

这是精确时间，永远不代表作品创作时间。

### `creationDateStart` / `creationDateEnd`

模糊时间区间：

- 2024 年：2024-01-01 至 2024-12-31；
- 2023 年夏天：对应季节范围；
- 5～6 岁：可结合生日换算为日期范围；
- 幼儿园时期：可以有估算区间，也可以只保存 label。

### `timelineSortKey`

用于稳定排序，不直接展示给用户。

建议优先级：

1. 精确日期；
2. 日期区间中点；
3. 年龄区间中点换算；
4. life stage 排序；
5. 手动排序；
6. unknown 为 nil。

### `displaySeed`

用于生成稳定的：

- 左右侧；
- 旋转角；
- 水平偏移；
- section 内纵向偏移。

不要依赖 Swift 默认 `hashValue` 作为持久化 seed，因为跨进程或系统版本可能不稳定。创建作品时生成并持久化一个固定整数，或使用稳定哈希。

## 7.5 数据迁移

现有作品迁移规则：

1. 已经有明确创作时间的作品：
   - `reviewState = reviewed`
   - `placementState = placed` 或 `approximate`
2. 当前以 capture date 保存、但无法判断是否真实创作时间的作品：
   - 不要自动清空；
   - 如果仓库没有来源区分，保留现状，避免破坏用户数据；
   - 新作品开始执行正确语义。
3. 已明确 unknown 的作品：
   - `reviewState = reviewed`
   - `placementState = unplaced`
4. `displaySeed` 缺失时生成并持久化。
5. 迁移必须幂等。

---

# 8. 拍摄与导入流程改造

## 8.1 当前问题

当前 Camera 和 Photos Picker 会逐张创建作品，并倾向于把 `capturedDate` 作为 `createdAround`。

同时仓库中已经存在一套未充分接入主流程的 batch review UI。应优先复用和重构，而不是重新创建完全重复的页面。

## 8.2 新流程

```text
开始拍摄 / 选择照片
→ 每张原图立即写入本地
→ 创建 LocalWork
→ capturedAt = 当前时间或原始照片导入时间
→ creation time = unknown
→ reviewState = pending
→ 收集本次 work IDs
→ 用户点击 Done / 照片导入完成
→ 打开 BatchReviewView
```

## 8.3 安全保存原则

不要为了等 Batch Review 完成才创建作品。

正确顺序：

1. 原图写入；
2. SwiftData record 写入；
3. 生成缩略图；
4. 后台同步；
5. 后台 AI；
6. 用户可以稍后补充时间。

即使 App 在拍摄第 20 张时被系统杀死，前 19 张也必须存在。

## 8.4 建议新增协调层

```swift
@MainActor
final class CaptureBatchCoordinator: ObservableObject {
    @Published private(set) var workIDs: [UUID] = []
    @Published var isReviewPresented = false

    func appendCreatedWork(_ id: UUID)
    func finishCapture()
    func abandonReviewWithoutDeleting()
    func reset()
}
```

Camera 和 Photos Picker 都使用同一个 coordinator。

不要在两个入口分别复制归档逻辑。

## 8.5 Batch Review

界面以缩略图网格为主，只问最少信息。

### 默认字段

单孩子 MVP 下不需要每次询问 creator。

主要问题：

> 这些作品大概是什么时候画的？

选项：

- 最近画的；
- 大约几岁；
- 某一年；
- 某个季节；
- 成长阶段；
- 完全不记得。

可选补充：

- Drawing；
- Craft；
- Object；
- Other。

### 批量优先

- 用户选择一个时间，默认应用整批；
- 允许点单张进行 override；
- 清晰显示哪些作品使用批量值，哪些单独修改；
- 保存按钮文案使用“放进时间轴”；
- 次要按钮使用“以后再想”。

### “最近画的”

只有用户主动选择“最近画的”，才可以将 capture date 映射为创作日期。

不可默认这样做。

### “以后再想”

- 不删除作品；
- `reviewState = pending` 或 `reviewed + unplaced`，根据实现统一；
- `placementState = unplaced`；
- 作品可以立即在 Gallery、Search 和 Mac 中出现；
- 后续通过 Timeline 两侧再次浮现。

---

# 9. 作品详情与时间编辑

当前编辑器主要支持标题、孩子原话、家长备注和删除。需要增加“创作时间”编辑。

## 9.1 入口

Artwork Detail 中增加一行：

```text
创作时间
幼儿园时期 >
```

或：

```text
创作时间
还没想起来 >
```

## 9.2 编辑界面

复用 Batch Review 的单件时间选择器：

- 准确日期；
- 年月；
- 年份；
- 季节；
- 年龄；
- 年龄范围；
- 成长阶段；
- 完全未知。

修改后：

- 重算 `timelineSortKey`；
- 重算所属 section；
- 更新 `placementState`；
- 触发本地 UI 更新和正常同步；
- 不重新上传原图；
- 不需要重新运行完整 AI 分析。

---

# 10. Timeline 结构

## 10.1 推荐 SwiftUI 结构

不要第一版就使用自由 Canvas。

使用正常的滚动列表，在 section 上挂载侧边浮层：

```swift
ScrollView {
    LazyVStack(spacing: ...) {
        ForEach(viewModel.sections) { section in
            TimelineSectionView(section: section)
                .overlay {
                    FloatingWorksOverlay(
                        section: section,
                        items: viewModel.floatingItems(for: section)
                    )
                }
        }
    }
}
```

或者：

```swift
ZStack {
    TimelineContent()
    FloatingArtworkLayer()
}
```

优先选择 section overlay，因为：

- 更容易让浮动作品跟随 section 滚动；
- 不需要维护全页面绝对坐标；
- 点击区域和 VoiceOver 更容易处理；
- 性能更可控；
- 可以自然获取“附近时间段”。

## 10.2 中央内容宽度

iPhone 没有真正宽阔的左右栏。应主动给两侧留出视觉空间。

建议基于 GeometryReader 动态计算：

- 小屏设备：中央内容约占 68%～74%；
- 大屏设备：中央内容约占 72%～78%；
- 浮动卡片宽度：44～72 pt；
- 重点卡最大不超过 88 pt；
- 每个 section 最多 2 张，左右各最多 1 张。

不要硬编码只适配单一 iPhone 尺寸。

## 10.3 Timeline Section

MVP 可从现有时间数据推导 section：

- 精确年份或年龄；
- 大约年龄；
- life stage；
- 更早以前。

建议展示文案：

- `7 岁`
- `大约 5～6 岁`
- `幼儿园时期`
- `刚上一年级`
- `更早以前`

不要展示：

- `confidence = 0.42`
- `2022-01-01 ~ 2023-12-31`

---

# 11. 两侧未定位作品布局

## 11.1 候选选择

每次 Timeline session 创建一个稳定的 `surfaceEpoch`。

候选作品：

```text
placementState == unplaced
AND image exists
AND snoozedUntil <= now
AND not already surfaced in this session
```

优先级：

1. `surfaceCount` 少；
2. `lastSurfacedAt` 更早；
3. 随机打散；
4. 避免短期重复。

## 11.2 展示密度

建议：

- 每个 section：0～2 张；
- 左右各最多 1 张；
- 同屏总数建议不超过 4～6 张；
- 未定位作品很多时也不要提升密度；
- 滚动到新 section 后再出现新的候选。

## 11.3 稳定随机

“随机”只能在选择和布局初始化时发生，不能在 SwiftUI 每次 body 重算时发生。

使用：

```swift
layoutSeed = stableHash(work.displaySeed, surfaceEpoch, section.id)
```

从 seed 推导：

```swift
side
rotation
horizontalInset
verticalFraction
scaleVariant
```

范围建议：

- rotation：`-4°...4°`
- opacity：`0.88...1.0`
- scale：`0.92...1.04`
- vertical position：避开 section 标题和主要作品
- 屏幕边缘裁切：最多约 10%～18%

同一 session 中：

- 屏幕旋转或 view refresh 不应导致作品跳来跳去；
- 数据更新后仅受影响的卡片变化；
- 归位后该卡消失，其他卡不大范围重新排布。

## 11.4 视觉样式

未定位作品：

- 小卡；
- 轻微旋转；
- 轻微阴影；
- 无时间文字；
- 可选极轻的纸张边框；
- 不要统一加问号；
- 不要使用警告色。

正式时间轴作品：

- 更大；
- 对齐；
- 旋转归零；
- 清晰显示所属阶段；
- 视觉稳定。

## 11.5 不要暗示 AI 已确认

浮现在某 section 附近，只是记忆触发，不表示系统判断它属于该时期。

点击 Sheet 中使用疑问语气：

> 这张属于附近这段时间吗？

不要写：

> AI 判断这是 5 岁作品。

---

# 12. 归位交互

## 12.1 点击是 P0

点击侧边作品打开 bottom sheet 或 detent sheet。

内容：

1. 作品大图；
2. 附近阶段名称；
3. 主要按钮：`就是这段时间`；
4. 次要按钮：`比这更早`；
5. 次要按钮：`比这更晚`；
6. `选择其他时间`；
7. `还没想起来`。

## 12.2 P0 中“更早 / 更晚”的语义

不要在第一版建立复杂相对关系图。

建议实现为：

- 更早：移动到相邻的更早 section 作为新候选，再让用户确认；
- 更晚：移动到相邻的更晚 section 作为新候选，再让用户确认；
- 用户也可直接进入完整时间选择器。

如果产品希望一次点击即保存相对关系，可预留模型字段，但不要为了它拖慢 P0。

## 12.3 “就是这段时间”

映射规则：

- 精确年龄 section：保存为该年龄，confidence = approximate 或 confirmed；
- 年龄范围 section：保存为该范围；
- life stage section：保存 lifeStageID；
- year section：保存 year；
- 所有归位操作标记为用户确认。

## 12.4 “还没想起来”

- 关闭 sheet；
- `snoozedUntil` 设置为建议 14 天后；
- 不增加负面状态；
- 可增加 `surfaceCount`；
- 当前 session 不再展示该作品。

## 12.5 Undo

归位后在底部显示短暂 Undo：

```text
已放入「大约 5～6 岁」    撤销
```

Undo 恢复：

- 原创建时间；
- placement state；
- sort key；
- 原有 review state；
- 浮动候选状态。

---

# 13. 动画

动画必须克制，不要做成游戏化任务。

## 13.1 归位动画

推荐：

1. 卡片 scale 到 1.04；
2. 阴影短暂增加；
3. rotation 回到 0；
4. matched geometry 或近似 transition 移向目标 section；
5. 中央卡片淡入；
6. 侧边位置淡出。

时长建议约 350～550 ms，使用 spring 但避免强烈弹跳。

## 13.2 Reduce Motion

检测系统 Reduce Motion：

- 使用淡入淡出；
- 不做跨区域移动；
- 保持功能完整。

---

# 14. 小屏与无障碍

## 14.1 小屏降级

当可用宽度不足、横屏、Split View 或 Dynamic Type 很大时，不强行保留左右散落布局。

降级为 section 内的轻量横向“记忆碎片条”：

```text
一些还没找到时间的作品
[图] [图]
```

仍然保持相同点击归位流程。

## 14.2 VoiceOver

每张未定位作品必须有明确 label：

```text
未定位时间的作品，标题：海底世界。双击尝试放入“大约 5～6 岁”。
```

不要只读“按钮”或文件名。

## 14.3 点击区域

视觉卡片可以很小，但 hit target 至少 44 × 44 pt。

---

# 15. AI 与同步调用链修复

## 15.1 潜在重复 AI 分析

当前创建流程需要重点核验：

- `createWork()` 是否同时调用了 Mac library copy；
- copy/import 是否带 `autoAnalyze: true`；
- 同时是否又显式调用了 `enqueueMacProcessing`。

如果两条路径都触发分析，同一作品可能被重复处理。

Codex 必须先追踪完整调用链，再采用以下任一方案：

### 方案 A：显式队列为唯一入口

- Mac copy/import 使用 `autoAnalyze: false`
- 成功后调用一次 `enqueueMacProcessing`

### 方案 B：Mac import 为唯一入口

- copy/import 使用 `autoAnalyze: true`
- iOS 不再额外调用 enqueue

优先选择与当前架构最一致、失败恢复最清晰的方案。

## 15.2 幂等键

无论采用哪种方案，后端或本地队列都应使用幂等键：

```text
workID + originalAssetChecksum + analysisVersion
```

同一版本同一原图只产生一次有效分析。

## 15.3 状态机

建议 AI 状态至少明确为：

```text
pending
queued
processing
complete
failed
```

重复 enqueue 不得创建并行任务。

## 15.4 与本功能关系

AI 可以正常分析 unknown-time 作品。

时间未知不得阻塞：

- Mac 同步；
- 标题生成；
- 标签；
- 搜索；
- 分享卡；
- Gallery 展示。

---

# 16. 其他当前代码问题与处理

## 16.1 Root flow 绕过已有 Batch Review

仓库已有 Capture batch/review 相关界面，但当前主 Add 流程仍直接逐张保存并使用 captured date。

处理：

- 提取可复用的 `BatchReviewView`；
- Camera 与 Photos Picker 都接入；
- 删除或合并重复状态；
- 不保留两个行为不同的导入流程。

## 16.2 编辑器缺少时间编辑

P0 修复，见第 9 节。

## 16.3 “Semantic Search”名实不符

如果当前只是字符串 `contains` 和少量规则 token：

- 本阶段不要实现大型 embedding 系统；
- 将 UI 文案调整为 `Search` 或 `Smart Search`；
- 保留未来 Mac 生成 embedding 的接口空间。

## 16.4 拍摄时间与创作时间混淆

这是 P0 数据问题，不是文案问题。

必须在：

- 模型；
- 创建方法；
- Photos Picker；
- Camera；
- Timeline grouping；
- Detail 展示；
- Search indexing；
- Mac payload

中统一区分。

## 16.5 不改 Mac 完全同步

之前可能会把“Mac 删除导致 iPhone 删除”视为风险，但这是明确的产品要求。

本任务中：

- 不修改 `mergeMacArtworks` 的完全镜像语义；
- 不把 iPhone 改成独立 source of truth；
- 不创建 remote_missing 保留副本逻辑；
- 只确保新增的时间字段和 review 状态正常参与既有同步。

---

# 17. ViewModel 与服务建议

## 17.1 `TimelineViewModel`

建议职责：

```swift
@MainActor
final class TimelineViewModel: ObservableObject {
    @Published private(set) var sections: [TimelineSectionModel]
    @Published private(set) var floatingAssignments: [TimelineSectionID: [FloatingWork]]

    func rebuildSections()
    func beginSurfaceSession()
    func floatingItems(for section: TimelineSectionModel) -> [FloatingWork]
    func place(_ work: LocalWork, into section: TimelineSectionModel)
    func moveCandidateEarlier(_ work: LocalWork, from section: TimelineSectionModel)
    func moveCandidateLater(_ work: LocalWork, from section: TimelineSectionModel)
    func snooze(_ work: LocalWork)
    func undoLastPlacement()
}
```

## 17.2 不在 View body 中做业务计算

避免在 `body` 中：

- 随机选作品；
- 写 SwiftData；
- 计算大量图片；
- 重建全部 section；
- 触发同步。

所有随机 assignment 在 ViewModel session 初始化时完成。

## 17.3 图片性能

- 浮动卡使用 thumbnail；
- 不加载原图；
- 使用现有 image cache；
- 快速滚动时不启动昂贵分析；
- 500～1000 件作品下保持流畅。

---

# 18. 建议文件与模块

最终路径以仓库结构为准，建议新增或拆分：

```text
Timeline/
  TimelineView.swift
  TimelineViewModel.swift
  TimelineSectionModel.swift
  TimelineSectionView.swift
  FloatingArtworkLayer.swift
  FloatingArtworkCard.swift
  PlaceArtworkSheet.swift
  TimelineLayoutEngine.swift

Capture/
  CaptureBatchCoordinator.swift
  BatchReviewView.swift
  CreationTimePicker.swift
  CreationTimeSelection.swift

Models/
  CreationTimeKind.swift
  CreationTimeDescriptor.swift
  TimelinePlacementState.swift
  ReviewState.swift

Services/
  TimelineGroupingService.swift
  FloatingArtworkSurfacingService.swift
  AnalysisJobCoordinator.swift
```

不要为了匹配此目录而破坏当前项目组织。重点是职责分离。

---

# 19. 实施顺序

## Commit 1：数据语义与迁移

- 增加 `capturedAt`；
- 增加模糊时间字段；
- 增加 placement/review 状态；
- 增加 stable display seed；
- 完成迁移；
- 补充模型测试。

## Commit 2：统一创建流程

- Camera 与 Photos Picker 都创建 unknown-time work；
- capturedAt 单独记录；
- 引入 CaptureBatchCoordinator；
- 确保中断不丢图。

## Commit 3：批量归档

- 接入或重构现有 Batch Review；
- 批量时间；
- 单张 override；
- “放进时间轴”；
- “以后再想”。

## Commit 4：详情页时间编辑

- CreationTimePicker；
- 重算 section 与 sort key；
- 正常同步。

## Commit 5：Timeline section 模型

- 统一 exact / approximate / life stage 分组；
- stable sorting；
- 未定位作品不进入普通时间 section。

## Commit 6：两侧浮动作品

- candidate selection；
- stable random layout；
- density control；
- thumbnail；
- compact-width fallback。

## Commit 7：归位交互与动画

- PlaceArtworkSheet；
- 就是这段时间；
- 更早 / 更晚；
- 完整时间选择；
- snooze；
- Undo；
- Reduce Motion。

## Commit 8：AI 调用幂等

- 核验重复触发；
- 收敛为单入口；
- 添加 idempotency；
- 状态机测试。

## Commit 9：文案、搜索命名和 QA

- 修正 Semantic Search 文案；
- VoiceOver；
- Dynamic Type；
- 性能；
- UI 测试；
- 回归同步。

---

# 20. 验收标准

## 数据与拍摄

- [ ] 拍摄旧作品时，系统不再默认把今天作为作品创作日期。
- [ ] `capturedAt` 始终存在。
- [ ] 用户选择“最近画的”后，才将拍摄时间用于创作时间。
- [ ] 连续拍摄 20 张，中途退出 App，已拍作品不丢失。
- [ ] 从 Photos Picker 选择多张后进入同一 Batch Review。
- [ ] 可整批选择“大约 5～6 岁”。
- [ ] 可对其中一张单独改成“幼儿园时期”。
- [ ] 点击“以后再想”不会删除作品。

## Timeline

- [ ] 已定位作品位于中央时间轴。
- [ ] 未定位作品少量分布在两侧。
- [ ] 每个 section 最多 2 张浮动作品。
- [ ] 同一浏览 session 中，卡片不会因 SwiftUI 重绘而跳位。
- [ ] 重新进入或隔天进入时，可以轮换其他未定位作品。
- [ ] 浮动卡不遮挡主要内容和导航。
- [ ] 小屏或大字号下正确降级为 inline memory strip。
- [ ] 点击浮动作品可以选择“就是这段时间”。
- [ ] 归位后作品立即进入中央 section。
- [ ] 可撤销归位。
- [ ] “还没想起来”后，本次 session 不再重复出现。

## 编辑与搜索

- [ ] 详情页可以修改模糊时间。
- [ ] 修改后 Timeline 立即更新。
- [ ] 搜索结果仍可找到 unknown-time 作品。
- [ ] UI 不再把规则匹配搜索误称为严格 Semantic Search。

## AI 与同步

- [ ] 一张作品只产生一个有效 AI 分析任务。
- [ ] 重复 enqueue 被幂等拦截。
- [ ] AI 失败不影响作品保存与时间归档。
- [ ] Mac 完全同步语义保持不变。
- [ ] 新增时间字段正常同步。
- [ ] Mac 删除后 iPhone 的镜像删除行为保持现状。

## 性能与无障碍

- [ ] 500 件作品下 Timeline 滚动无明显卡顿。
- [ ] 浮动卡只加载缩略图。
- [ ] VoiceOver 可以读出作品和附近阶段。
- [ ] 点击区域不小于 44 × 44 pt。
- [ ] Reduce Motion 下不执行强移动动画。

---

# 21. 测试清单

## 单元测试

1. `CreationTimeDescriptor` 的各类型转换。
2. 年龄范围结合生日转换成日期范围。
3. `timelineSortKey` 稳定。
4. 迁移重复运行不产生变化。
5. stable seed 在同一 surface epoch 下生成相同布局。
6. 不同 surface epoch 可产生不同候选。
7. snoozed work 不被选中。
8. least surfaced work 优先。
9. placement 后从 unplaced candidates 中移除。
10. Undo 恢复原状态。
11. AI enqueue 幂等。

## UI 测试

1. Camera 完成后打开 Batch Review。
2. Photos Picker 完成后打开相同 Batch Review。
3. 批量设置时间并保存。
4. 单件 override。
5. 跳过归档。
6. Timeline 显示侧边作品。
7. 点击归入当前 section。
8. 更早 / 更晚导航。
9. 还没想起来。
10. Undo。
11. 大字号降级布局。
12. VoiceOver label 存在。

## 手动回归

- 离线拍摄；
- Mac 不在线；
- Mac 恢复在线后同步；
- AI 分析失败；
- 原图缺失或缩略图生成失败；
- App 在 Batch Review 中被杀死；
- 设备旋转；
- 低内存；
- 大量历史作品；
- 删除作品；
- Mac 端删除并同步到 iPhone。

---

# 22. 推荐文案

## Batch Review

标题：

> 这些作品大概是什么时候画的？

选项：

- 最近画的
- 大约几岁
- 某一年
- 某个季节
- 成长阶段
- 完全不记得

按钮：

- 放进时间轴
- 以后再想

## Timeline 侧边作品

轻提示，可不常驻：

> 一些还没找到时间的作品

点击后：

> 想起这是什么时候了吗？

按钮：

- 就是这段时间
- 比这更早
- 比这更晚
- 选择其他时间
- 还没想起来

归位后：

> 已放入「大约 5～6 岁」

Undo：

> 撤销

## 详情页

字段：

> 创作时间

unknown：

> 还没想起来

---

# 23. 设计基调

Volio 不是：

- 数据管理 SaaS；
- 待办工具；
- AI 打标后台；
- 儿童卡通应用；
- 必须完整填写的家庭档案表格。

Volio 应该像：

- 安静的私人画册；
- 一条柔软但可信的成长河流；
- 被慢慢整理出来的记忆墙；
- 一套普通用户无需理解 AI 的智能档案。

视觉关键词：

- Editorial；
- Quiet；
- Warm；
- Tactile；
- Lightly playful；
- Human memory；
- Stable, not rigid。

---

# 24. 最终产品判断

这一版本完成后，Volio 的核心价值不再只是：

> 把孩子的画拍下来并自动分析。

而是：

> 即使你已经记不清准确日期，Volio 仍能帮你把每一幅作品慢慢放回成长故事。

请围绕这个核心判断实施，不要把功能退化成“给图片增加一个可为空的日期字段”，也不要只做随机散落的视觉装饰。数据语义、批量归档、时间编辑、浏览中归位和后台幂等必须一起构成完整闭环。
