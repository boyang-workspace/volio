# Volio iOS：Timeline 首页化、模糊时间轴视觉升级与性能优化实施文档

**文档用途**：直接交给 Codex，在当前 Volio iOS 工程上实施本轮修复。  
**仓库**：`boyang-workspace/volio`  
**检查日期**：2026-06-20  
**目标版本**：下一版内部可用构建  
**最高优先级**：性能、稳定性、布局正确性  
**产品方向**：Timeline 成为主体验；Gallery 退为全部作品管理入口。

---

## 0. 给 Codex 的执行说明

请先读取当前本地工作树和 GitHub `main`，以**本地最新代码**为准。

注意：检查到的 GitHub `main` 快照中，`TimelineView.swift` 仍主要是传统的年龄分组 + 方形网格；如果本地工作树已经存在“时间轴两侧散落未定位作品”的新实现，**绝对不要回退或覆盖它**。本任务是在该实现上进行性能、布局和交互修复。

执行约束：

1. 不做与本轮目标无关的大规模重构。
2. 保留 iPhone 与 Mac 的完全同步产品逻辑。
3. 保留 local-first：拍照后必须先可靠保存到本地。
4. 不增加重型第三方图片库。
5. deployment target 保持 iOS 17。
6. 本轮先固定浅色模式，不实现自动 Dark Mode。
7. 所有随机旋转、位置和卡片样式必须稳定，不得因 SwiftUI 重绘而跳动。
8. 所有原图读取、图片解码、缩略图生成和文件写入不得阻塞主线程。
9. 每个阶段完成后，使用 Release 构建在真机上测试；不要只观察 Simulator。
10. 先建立性能基线，再改动；改完后提供对比数据。

---

# 1. 本轮产品判断

## 1.1 Timeline 应成为首页

结论：**是。**

Volio 的核心价值已经不是“查看全部图片”，而是：

> 即使用户不记得准确日期，也能在浏览成长过程时，逐渐把作品放回属于它的时间。

因此导航层级调整为：

```text
Timeline     Gallery     Search     +
首页          全部作品      搜索       添加
```

建议：

- 默认选中 `Timeline`；
- 底部第一个 Tab 为 `Timeline`；
- `Gallery` 继续保留，承担“全部作品、批量选择、删除、快速查漏”；
- Gallery 不删除，也不隐藏；
- Timeline 的空状态必须提供明显但不压迫的拍摄入口；
- 所有详情、编辑和同步能力两端保持一致。

### 具体代码改动

当前 `RootTabsView` 默认：

```swift
@State private var selectedTab: MainTab = .gallery
@State private var lastContentTab: MainTab = .gallery
```

改为：

```swift
@State private var selectedTab: MainTab = .timeline
@State private var lastContentTab: MainTab = .timeline
```

同时：

```swift
static var contentTabs: [MainTab] { [.timeline, .gallery, .search] }
```

系统 `TabView` 和 Legacy Tab 的显示顺序都必须同步修改。

---

# 2. 当前代码审计结论

以下问题已经在当前仓库代码中确认。

## 2.1 启动时重复执行完整 setup

`ContentView.onAppear` 直接调用：

```swift
session.setup(context: modelContext)
```

`setup` 当前没有幂等保护，每次重新出现都可能再次：

- 读取本地配对信息；
- 获取全部作品；
- 获取全部 processing jobs；
- 执行迁移扫描；
- 启动 Mac refresh。

必须增加一次性 setup 状态。

建议：

```swift
private var didSetup = false

func setup(context: ModelContext) {
    guard !didSetup else { return }
    didSetup = true
    ...
}
```

如果 context 可能变化，单独处理 context 更新，不要重复完整初始化。

---

## 2.2 启动迁移存在 N+1 SwiftData 查询

当前 `migrateLegacyAssetsIfNeeded` 会：

1. 遍历全部 `works`；
2. 对每个 work 再执行一次 `FetchDescriptor<LocalAsset>`。

作品越多，首次启动越慢。

### 必须修改为单次批量读取

```swift
let allAssets = try context.fetch(FetchDescriptor<LocalAsset>())
let assetsByWorkID = Dictionary(grouping: allAssets, by: \.workId)

for work in works {
    let existing = assetsByWorkID[work.id] ?? []
    ...
}
```

迁移还必须增加版本标识，例如：

```swift
@AppStorage("volio.localMigrationVersion")
private var localMigrationVersion = 0
```

只有 migration version 低于目标版本时执行。

不要在每次启动扫描所有作品和资产。

---

## 2.3 首次启动立即触发完整 Mac refresh

当前 setup 在本地加载后马上：

```swift
Task { await refreshMacLibrary() }
```

`refreshMacLibrary` 会 bootstrap 全部 Mac artworks，并继续 merge、检查媒体、必要时下载图片。

虽然网络逻辑是 async，但会与首屏图片加载、SwiftUI 初始化和 SwiftData 更新同时发生，持续触发 UI observation 更新。

### 修改原则

首屏优先显示本地数据。

流程改为：

```text
读取最小本地数据
→ 显示 Timeline 首屏
→ 等待首帧完成
→ 低优先级启动 Mac 同步
```

建议：

```swift
Task(priority: .utility) {
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(500))
    guard scenePhase == .active else { return }
    await refreshMacLibrary()
}
```

要求：

- 同一时刻只能有一个 refresh；
- 多个 refresh 请求必须 coalesce；
- 进入详情页的单件 refresh 不得同时触发全库 refresh；
- pull-to-refresh 仍可立即执行；
- 保留 Mac 完全同步语义。

---

## 2.4 每张作品创建后都可能触发一次完整 Mac refresh

当前 `syncMacLibraryCopy` 上传一张作品后调用：

```swift
await refreshMacLibrary()
```

连续拍 20 张时，可能触发 20 次完整 refresh。

同时 `createWork` 当前还会：

```swift
syncMacLibraryCopy(...)
enqueueMacProcessing(...)
```

而 import 又带 `autoAnalyze: true`，存在重复分析风险。

### 必须改成 Batch Sync Coordinator

拍摄期间：

- 每张原图立即保存本地；
- 只将 work ID 加入待同步队列；
- 不逐张 refresh Mac library；
- 用户点击 Done 后，批量上传；
- 整批结束后最多 refresh 一次。

建议：

```swift
actor MacSyncCoordinator {
    func enqueue(workID: String)
    func flushBatch()
    func requestLibraryRefresh()
}
```

要求：

- 500–1000 ms debounce；
- 相同 work ID 去重；
- 同一批最多一次 bootstrap refresh；
- AI 分析只有一个入口；
- 幂等键：`workID + originalChecksum + analysisVersion`。

推荐选择：

```text
Mac import autoAnalyze = true
iOS 不再额外 enqueue 同一作品的处理任务
```

或者反过来，但不能两边同时触发。

---

## 2.5 图片加载没有共享缓存，并可能回退解码原图

目前 `LocalThumbnail` 和 `MasonryImage` 分别实现自己的加载逻辑：

- 每个 View 创建自己的 `@State UIImage`；
- 每次重新创建 View 都重新读取文件；
- 使用 `Data(contentsOf:) + UIImage(data:)`；
- 没有共享 `NSCache`；
- 缩略图不存在时直接读取原图；
- 初始 aspect ratio 与真实 ratio 不同，加载后会重新布局。

这会导致：

- 冷启动大量图片读取；
- Tab 切换重复解码；
- Timeline 滚动掉帧；
- 图片加载后卡片跳动；
- 弹窗初次布局尺寸错误；
- 内存峰值过高。

### 必须统一为一个图片管线

新增：

```text
ArtworkImagePipeline
CachedArtworkImage
ArtworkImageMetadata
```

管线职责：

1. 使用 `CGImageSourceCreateThumbnailAtIndex` 按目标像素尺寸 downsample；
2. 不使用 `UIImage(data:)` 解码整张原图作为列表图片；
3. 使用共享 `NSCache`；
4. 支持 Task cancellation；
5. cache key 包含：
   - work ID；
   - 文件修改时间或 checksum；
   - 目标 pixel size；
6. 收到 memory warning 时清理缓存；
7. 列表、Timeline、弹窗和拍摄 Review 使用同一组件。

建议 API：

```swift
struct CachedArtworkImage: View {
    let workID: String
    let thumbnailPath: String?
    let originalPath: String?
    let targetSize: CGSize
    let contentMode: ContentMode
    let aspectRatio: CGFloat
}
```

---

## 2.6 新作品初始 thumbnailPath 指向 originalPath

当前创建作品时：

```swift
thumbnailPath: originalPath
```

这会使首屏在真正缩略图生成前直接加载原图。

### 修改方式

不要把 original path 临时冒充 thumbnail path。

方案：

1. Camera 已生成小 preview，直接把 preview 保存为初始 thumbnail；
2. Photos Picker 导入时，后台先生成 300–600 px thumbnail；
3. `thumbnailPath` 在缩略图文件真实存在后再写入；
4. fallback 到 original 时也必须通过 ImageIO downsample，不能全尺寸 decode。

---

## 2.7 主线程执行文件写入和部分图片处理

`VolioSession` 是 `@MainActor`，`createWork()` 当前同步执行：

```swift
ImageStorage.saveOriginal(id:data:)
```

这是完整 JPEG 文件写入。

Camera 的 `onCapture` 直接调用 `session.createWork`，因此连续拍照时主线程可能被文件 I/O 和 SwiftData save 阻塞。

### 必须拆分 Capture Ingest

新增：

```swift
actor ImageIngestService
```

职责：

- 生成 work ID；
- 写 original；
- 写初始 preview/thumbnail；
- 提取 width、height、orientation；
- 计算 checksum；
- 返回轻量结果。

```swift
struct IngestedImage {
    let workID: String
    let originalPath: String
    let thumbnailPath: String
    let pixelWidth: Int
    let pixelHeight: Int
    let checksum: String
}
```

主线程只负责：

- 插入 SwiftData record；
- 更新小量 observable state。

拍照回调：

```swift
Task {
    let result = await ingestService.ingest(payload)
    await session.insertIngestedWork(result)
}
```

不能在相机 delegate 主线程同步写原图。

---

# 3. 固定浅色模式

## 3.1 当前问题

当前代码没有主动添加 Dark Mode，但 App 会默认跟随系统外观。

同时 Volio 使用固定浅色：

```swift
VolioTheme.paper
VolioTheme.card
```

但部分文字、控件和 UIKit 元素仍使用：

```swift
.primary
.secondary
.tertiary
UIColor.secondaryLabel
systemGroupedBackground
ultraThinMaterial
```

在系统进入 Dark Mode 后，会出现：

- 固定浅色背景；
- 系统动态文字变成白色；
- 白字落在浅色卡片上；
- Material 和 tab bar 颜色不一致。

## 3.2 本轮处理

先明确固定为 Light Mode。

在 `Info.plist` 增加：

```xml
<key>UIUserInterfaceStyle</key>
<string>Light</string>
```

同时在 App root 保持一致：

```swift
ContentView()
    .preferredColorScheme(.light)
```

至少保留一种全局强制方式；建议 Info.plist 为主，root 作为 SwiftUI 防护。

此外，在所有 Volio 自定义浅色 surface 上：

- 主文字使用 `VolioTheme.ink`；
- 次级文字使用 `VolioTheme.mutedInk`；
- 不混用 `.primary/.secondary`；
- 系统原生 List/Picker 可继续使用系统颜色，因为整个 App 已固定 light。

本轮不创建完整 dark palette。

---

# 4. “+”按钮响应区域修复

## 4.1 已确认根因

iOS 18+ 的底部右侧当前覆盖了一个透明按钮：

```swift
Color.clear
    .frame(width: 112, height: 104)
    .contentShape(Rectangle())
```

这就是点击“+”上方大片空白仍会呼出菜单的原因。

## 4.2 修改方案

优先删除 `AddTabTouchShield`，直接依赖 `TabView` selection interception：

```swift
if newValue == .capture {
    toggleAddMenu()
    selectedTab = lastContentTab
}
```

如果真机测试发现系统 prominent tab 必须额外覆盖：

- hit target 最大 64 × 64 pt；
- `contentShape(Circle())`；
- 与可见 + 按钮严格居中；
- 不允许矩形透明区域延伸到按钮上方；
- VoiceOver frame 与视觉按钮一致。

验收：

- 点击 + 按钮可靠触发；
- 点击按钮上方 10 pt 以外的空白不触发；
- 点击附近 Gallery/Search Tab 不被拦截。

---

# 5. Timeline 两侧作品视觉升级

## 5.1 目标

中间时间轴保持稳定、清晰。

两侧未定位作品：

- 比当前稍大；
- 使用原始图片比例；
- 有轻微稳定倾斜；
- 有柔和阴影；
- 滚动时具有轻微深度差；
- 不抢夺中央时间轴的阅读权重；
- 不造成卡顿。

## 5.2 图片尺寸

建议基于设备宽度动态计算：

```text
小屏：68–88 pt 宽
普通屏：78–104 pt 宽
大屏：88–118 pt 宽
最大高度：150 pt
```

不能统一方形。

使用真实 aspect ratio：

```swift
let ratio = CGFloat(pixelWidth) / CGFloat(pixelHeight)
```

限制极端比例：

```swift
let clampedRatio = min(max(ratio, 0.55), 1.65)
```

渲染：

```swift
CachedArtworkImage(...)
    .aspectRatio(clampedRatio, contentMode: .fit)
```

不使用 `.scaledToFill()` 强制裁方形。

## 5.3 图片宽高元数据

`LocalAsset` 已有：

```swift
width
height
```

但创建时没有充分写入。

本轮必须：

- Camera capture 时通过 ImageIO 提取 pixel width/height；
- Photos Picker 导入时同样提取；
- 写入 original LocalAsset；
- 已有作品缺失时在后台懒回填；
- Timeline 布局只读取 metadata，不为计算比例读取完整图片。

## 5.4 稳定随机样式

每张未定位作品生成并持久化稳定 seed，或使用稳定 UUID hash。

从 seed 推导：

```text
left / right
rotation: -3.5° ... 3.5°
width variant
vertical offset
shadow variant
```

禁止在 View body 内调用 `Double.random`。

同一 App session 中位置必须稳定。

## 5.5 视觉滚动差 / Parallax

目标不是强烈漂浮，而是侧边作品比中央内容稍慢，形成轻微纵深。

建议视觉速度：

```text
中央 Timeline：1.00x
侧边作品：0.82x–0.90x
```

### 性能要求

不要用一个全局 `@State scrollOffset` 每帧驱动整页重新计算。

优先使用 iOS 17 的 `visualEffect` 对少量浮动卡片施加 render transform：

```swift
.visualEffect { content, proxy in
    let frame = proxy.frame(in: .scrollView(axis: .vertical))
    let depthOffset = parallaxOffset(for: frame)
    content.offset(y: depthOffset)
}
```

要求：

- 同屏浮动卡最多 4–6 张；
- 每个 section 最多 2 张；
- transform 只改变 offset/scale/opacity；
- 不在滚动时重新解码图片；
- 不在滚动时重新随机分配；
- Reduce Motion 开启时关闭 parallax；
- 滚动快速时不触发任何文件 I/O。

建议幅度：

```text
最大额外 offset：±18–28 pt
scale：0.98–1.02
```

不要做大幅漂移。

---

# 6. 点击散落作品后的弹窗布局修复

## 6.1 用户观察

第一次点击两侧散落图片时：

- 弹窗元素异常放大；
- 超出左右边界；
- 加载一段时间后恢复。

## 6.2 可能根因

结合当前图片组件，优先排查：

1. 图片真实比例在异步加载后才得到，导致首次 layout 使用错误尺寸；
2. placeholder 没有稳定 aspect ratio；
3. sheet 内容使用图片 intrinsic size；
4. `.fixedSize(horizontal: true)` 或 `UIScreen.main.bounds`；
5. GeometryReader 初始宽度为 0 或异常；
6. full-screen dismiss 与 sheet presentation 同时发生；
7. 原图 decode 完成后才触发正确 layout。

## 6.3 强制布局规则

归位 Sheet 外层：

```swift
GeometryReader { proxy in
    let contentWidth = min(max(proxy.size.width - 32, 280), 440)

    ScrollView {
        VStack(spacing: 16) {
            ...
        }
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity)
    }
}
```

要求：

- 所有按钮在 `contentWidth` 内；
- 不使用图片 intrinsic width 决定容器；
- 图片加载前后占位尺寸一致；
- image aspect ratio 从 metadata 读取；
- sheet 初次展示时不依赖图片解码结果；
- 文案允许换行；
- Dynamic Type 下仍不横向溢出。

建议：

```swift
.presentationDetents([.medium, .large])
.presentationDragIndicator(.visible)
.presentationContentInteraction(.scrolls)
```

如果内容在 `.medium` 放不下，默认直接 `.large`。

## 6.4 Presentation 状态机

不要在 camera/fullScreenCover 还在 dismiss 动画时立即 present sheet。

使用：

```swift
enum RootPresentation {
    case none
    case camera
    case batchReview([String])
    case placement(String)
}
```

或者：

- Camera `onDone` 只设置 pending batch；
- `fullScreenCover(onDismiss:)` 再打开 sheet。

同一时间只能存在一个 modal presentation。

---

# 7. 拍照 Done 后的 Batch Review 新设计

## 7.1 目标

点击 Camera 的 Done 后，弹出一个大面板：

```text
┌──────────────────────────┐
│      横滑作品卡片区域       │
│    [ 前一张 ][当前][下一张]  │
│                          │
│  这些作品大概什么时候画的？  │
│  时间选项 / 类型 / 按钮      │
└──────────────────────────┘
```

上半部分用于回看作品，下半部分用于批量设置模糊时间。

## 7.2 Camera API 改造

当前 `StackCameraView` 只有：

```swift
onCapture
onClose
```

Done 直接调用 close，没有独立完成语义。

改为：

```swift
struct StackCameraView: UIViewControllerRepresentable {
    let onCapture: (CapturedImagePayload) -> Void
    let onDone: () -> Void
    let onCancel: () -> Void
}
```

UIKit Controller：

```swift
var onDone: (() -> Void)?
var onCancel: (() -> Void)?
```

Done：

- 停止 session；
- 调用 `onDone`；
- Root presentation state 在 dismiss 完成后展示 Batch Review。

## 7.3 Capture Batch 状态

新增：

```swift
@MainActor
@Observable
final class CaptureBatchSession {
    var workIDs: [String] = []
    var selectedIndex = 0

    func append(_ workID: String)
    func remove(_ workID: String)
    func reset()
}
```

注意：

- 拍照时作品已经保存；
- Batch Review 不持有所有原图 Data；
- 只持有 ID 和轻量 metadata；
- 图片显示使用本地 thumbnail；
- App 被杀后作品仍存在；
- 未完成 review 的作品标记为 unplaced。

## 7.4 上半部横滑作品

使用 iOS 17：

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 12) {
        ...
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)
.scrollIndicators(.hidden)
```

也可以使用 paging `TabView`，但 Horizontal ScrollView 更适合露出前后卡片。

卡片：

- 宽度约 sheet 可用宽度的 72%–80%；
- 两侧露出下一张；
- 使用原始比例；
- 最大高度约 300 pt；
- 稳定随机旋转 `-2°...2°`；
- 柔和阴影；
- 当前卡 scale 1；
- 非当前卡 scale 0.94–0.97；
- 不加载原图，只使用 600 px thumbnail；
- 一张照片时居中；
- 页面指示 `3 / 12`；
- 支持删除当前张，但必须二次确认或提供 Undo。

柔和投影建议：

```swift
.shadow(
    color: Color.black.opacity(0.10),
    radius: 14,
    x: 0,
    y: 7
)
```

## 7.5 下半部时间选择

保留此前的模糊时间逻辑：

- 最近画的；
- 大约几岁；
- 某一年；
- 某个季节；
- 成长阶段；
- 完全不记得。

默认整批应用。

支持：

- 当前照片单独修改；
- 显示“使用批量设置”；
- “Add More” 返回相机，保留 batch；
- “放进时间轴”；
- “以后再想”。

## 7.6 不要重复保存

当前旧 Capture Review 中可能先保留 Data，最后 `Save All` 再 `createWork`。

新流程中作品已经在拍摄时安全落盘，Done 后的面板只更新 metadata。

禁止再次创建 LocalWork 或复制原图。

---

# 8. 相机启动性能

## 8.1 当前问题

当前每次打开 Camera：

- 新建 `StackCameraViewController`；
- 新建 `AVCaptureSession`；
- 重新 discovery device；
- 重新添加 input/output；
- 启动 session。

当前所谓 prewarm 只提前请求 camera permission，没有预配置 session。

## 8.2 优化方式

新增可复用：

```swift
final class CameraSessionController
```

生命周期：

- App session 内复用已配置的 `AVCaptureSession`；
- 第一次打开时 configure；
- 关闭时 stopRunning，但不销毁 input/output；
- 第二次打开只 startRunning；
- 进入后台时 stop；
- memory pressure 时可释放。

Add 菜单打开时：

```swift
cameraSession.prepareIfNeeded()
```

注意：

- prepare 不应在 App 冷启动立即抢占资源；
- 用户点击 + 或相机入口后再开始；
- session start/stop 始终在 serial queue；
- UIKit overlay 可以立即显示，不等待 preview live；
- 显示轻量 camera placeholder，不能长时间黑屏无反馈。

## 8.3 拍照后的性能

Camera delegate 已生成 120 px preview。

扩展 payload：

```swift
struct CapturedImagePayload {
    let originalData: Data
    let previewImage: UIImage?
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: CGImagePropertyOrientation?
}
```

优先用 preview 构建初始 thumbnail，不要再次同步解码原图。

---

# 9. Tab 切换性能

## 9.1 LegacyRootTabs 当前问题

Legacy 逻辑通过：

```swift
switch selectedTab
```

直接替换 View。

这会销毁并重建页面状态，导致：

- 图片重新加载；
- NavigationStack 重建；
- 页面切换明显卡顿；
- scroll position 丢失。

## 9.2 修改建议

iOS 17+ 统一使用原生 `TabView(selection:)` 承载三个内容页面。

可以继续叠加自定义底栏，但不要通过 switch 销毁页面。

目标：

- 已访问 Tab 保持 scroll position；
- 图片命中共享 cache；
- 切换时不读取磁盘；
- 第一次访问某 Tab 才创建其重内容。

如果原生 TabView 导致全部页面首启同时加载，应实现 `LazyTabHost`：

```text
Timeline 首次立即创建
Gallery 第一次点击后创建并保留
Search 第一次点击后创建并保留
```

不要为了保持状态而在冷启动同时加载三个页面的所有图片。

---

# 10. Timeline 数据计算性能

当前 Timeline 的 `groups` 是 computed property，每次 body 更新都会：

- Dictionary grouping；
- 每组排序；
- 全部分组排序。

Gallery 也会在 View body 中对 works 排序。

### 修改方案

增加只在数据变更时更新的 index：

```swift
@MainActor
@Observable
final class TimelineIndex {
    private(set) var sections: [TimelineSectionModel] = []

    func rebuild(from works: [LocalWork])
    func apply(inserted work: LocalWork)
    func apply(updated work: LocalWork)
    func apply(deletedID: String)
}
```

要求：

- Timeline 滚动不重建 sections；
- sheet 打开不重建全部 groups；
- 一张作品归位只更新原 section、目标 section和浮动候选；
- 不能因为 `processingStatus` 改变就重新分组全部作品；
- 未定位作品候选在 session 开始时分配一次。

---

# 11. Performance Instrumentation

在 Release/Profiling 配置加入 `os_signpost`：

```text
app_setup
swiftdata_fetch
legacy_migration
first_timeline_render
thumbnail_decode
thumbnail_cache_hit
camera_prepare
camera_preview_live
capture_ingest
mac_batch_sync
tab_switch
placement_sheet_present
batch_review_present
```

至少记录：

- start；
- end；
- work count；
- image size；
- cache hit/miss；
- batch count。

使用 Instruments：

- Time Profiler；
- SwiftUI；
- Core Animation；
- Allocations；
- File Activity；
- Network。

不要只凭“感觉更快”验收。

---

# 12. 性能预算

以 Release 真机、约 500 幅作品为基准。

## 启动

- 首帧：目标 ≤ 500 ms；
- Timeline 可交互：目标 ≤ 1.0 s；
- 启动主线程不可出现 >100 ms 的连续文件 I/O；
- migration 已完成后，后续启动不再扫描全部 assets。

## 页面切换

- 已访问 Tab 切换：目标 ≤ 120 ms；
- 不出现空白网格；
- 不重复批量解码首屏图片；
- 保持 scroll position。

## Timeline 滚动

- 目标接近 60 fps；
- 快速滚动无明显停顿；
- 同屏仅加载可见和少量预取图片；
- 不加载原图；
- parallax 不触发 ViewModel 大范围重算。

## Camera

- 点击入口后全屏 UI 出现：≤ 150 ms；
- 首次 preview live：目标 ≤ 700 ms；
- 第二次打开 preview live：目标 ≤ 350 ms；
- shutter 点击后 UI feedback：≤ 100 ms；
- 保存原图不得阻塞快门按钮。

## Sheet

- 点击散落作品后 sheet 可见：≤ 200 ms；
- 初始尺寸与加载后尺寸一致；
- 无横向溢出；
- Batch Review 首张缩略图：≤ 250 ms。

这些是优化目标，不要求为了数字牺牲数据安全。

---

# 13. 推荐实施顺序

## Commit 1：建立基线与强制 Light Mode

- 添加 signpost；
- 记录当前启动、Tab、Camera 数据；
- Info.plist 固定 Light；
- 清理浅色 surface 上的动态文字颜色。

## Commit 2：修复启动 hot path

- setup 幂等；
- migration version；
- 消除 LocalAsset N+1；
- Mac sync 延后且 coalesce；
- 确保首屏只读本地数据。

## Commit 3：统一图片管线

- ArtworkImagePipeline；
- NSCache；
- ImageIO downsample；
- metadata aspect ratio；
- 替换 LocalThumbnail/MasonryImage 重复实现；
- 禁止列表解码原图。

## Commit 4：异步 Capture Ingest

- 文件写入移出 MainActor；
- 保存 preview thumbnail；
- width/height/checksum；
- camera capture 连拍不卡顿。

## Commit 5：Timeline 首页化与 Tab 保活

- 默认 Timeline；
- 调整 Tab 顺序；
- Gallery 次级；
- 修复 Legacy switch 重建；
- 保持导航与 scroll state。

## Commit 6：+ 命中区域

- 移除 112×104 shield；
- 使用 selection interception；
- 必要时仅保留 56–64 pt 圆形 hit target；
- 真机回归。

## Commit 7：两侧作品自然比例与 Parallax

- 更大卡片；
- 原始比例；
- 稳定倾斜；
- GPU render transform；
- Reduce Motion；
- 同屏密度限制。

## Commit 8：散落作品 Sheet 修复

- 固定首次 layout；
- metadata placeholder；
- modal 状态机；
- 无横向溢出；
- Dynamic Type。

## Commit 9：Done 后 Batch Review

- Camera 独立 onDone；
- dismiss 后 present；
- 上半部横滑作品；
- 原始比例；
- 随机倾斜和柔和阴影；
- 下半部模糊时间；
- metadata-only update；
- Add More。

## Commit 10：Mac Batch Sync 与 AI 幂等

- 拍摄期间只入队；
- Done 后整批同步；
- 整批最多 refresh 一次；
- 取消重复 AI trigger；
- 保持完全同步。

## Commit 11：Instruments 回归和测试

- 性能对比；
- 内存；
- 大数据量；
- 离线；
- Mac 在线/离线；
- 深色系统环境下仍保持 Light；
- iPhone 小屏/大屏；
- Dynamic Type；
- Reduce Motion。

---

# 14. 验收标准

## 产品结构

- [ ] App 冷启动默认进入 Timeline。
- [ ] 底栏顺序为 Timeline、Gallery、Search、+。
- [ ] Gallery 仍可查看所有作品、选择和删除。
- [ ] Timeline 空状态可直接引导拍摄。

## Dark Mode

- [ ] 系统设置为 Dark 时，Volio 仍使用完整浅色界面。
- [ ] 不再出现浅色背景上的白色文字。
- [ ] Sheet、Tab、Settings 和 Editor 均一致。
- [ ] 本轮没有半套 Dark Mode 残留。

## + 按钮

- [ ] 只有视觉按钮附近 56–64 pt 范围可触发。
- [ ] 按钮上方空白不触发。
- [ ] 不遮挡相邻 Tab。

## 启动与切换

- [ ] setup 只执行一次。
- [ ] migration 不再每次启动运行。
- [ ] 不存在每幅作品一次的 LocalAsset fetch。
- [ ] 首屏展示前不执行完整 Mac merge/download。
- [ ] Tab 切换不重复加载已缓存图片。
- [ ] Scroll position 被保留。

## 图片

- [ ] 列表和 Timeline 使用 downsample thumbnail。
- [ ] 图片加载前后卡片尺寸不跳动。
- [ ] 不因 thumbnail 缺失而全尺寸 decode original。
- [ ] 共享 cache 生效。
- [ ] 内存警告后可释放 cache。

## Timeline 视觉

- [ ] 两侧作品尺寸比当前更大，但不遮挡中央内容。
- [ ] 图片使用原始比例，不统一裁正方形。
- [ ] 倾斜角稳定。
- [ ] 滚动时有轻微视差。
- [ ] Reduce Motion 时关闭视差。
- [ ] 快速滚动无明显掉帧。

## 散落作品弹窗

- [ ] 第一次打开就保持正确宽度。
- [ ] 加载图片前后布局不改变。
- [ ] 不超出左右 safe area。
- [ ] 小屏、横屏和大字号正常。
- [ ] 打开速度符合预算。

## Camera 与 Review

- [ ] 第一次打开 Camera 明显加快。
- [ ] 第二次打开复用已配置 session。
- [ ] 连续拍摄不因文件写入卡住快门。
- [ ] 点击 Done 后先退出 Camera，再打开 Batch Review。
- [ ] Batch Review 上半部可逐张横滑。
- [ ] 卡片显示原始比例。
- [ ] 卡片有轻微稳定倾斜和柔和阴影。
- [ ] 上一张和下一张有适当露出。
- [ ] Review 不保留所有原图 Data。
- [ ] “放进时间轴”只更新 metadata，不重复创建作品。
- [ ] “以后再想”保留为未定位作品。
- [ ] “Add More”返回 Camera 后 batch 不丢失。

## Mac 同步

- [ ] 连拍一批不会逐张执行全库 refresh。
- [ ] 整批同步后最多 refresh 一次。
- [ ] 同一作品没有重复 AI 分析任务。
- [ ] iPhone 与 Mac 的完全同步语义保持不变。

---

# 15. 必须添加的测试

## 单元测试

1. setup 幂等。
2. migration version。
3. 单次批量 asset mapping。
4. stable aspect ratio。
5. stable random rotation。
6. thumbnail cache key。
7. cache hit 不重新读取文件。
8. Batch Sync 去重。
9. AI enqueue 幂等。
10. Capture Batch metadata update 不创建重复 LocalWork。
11. Timeline index 增量更新。
12. unplaced → placed 的 section 更新。

## UI 测试

1. 冷启动默认 Timeline。
2. 系统 Dark 下 App 保持 Light。
3. + 上方空白不会触发。
4. + 本体触发菜单。
5. 点击散落作品首次 sheet 不溢出。
6. sheet 图片加载前后 frame 不变化。
7. Camera Done 后 Batch Review。
8. Batch Review 横滑。
9. Add More。
10. 放进时间轴。
11. 以后再想。
12. Tab 切换保持 scroll position。
13. Reduce Motion 下无 parallax。
14. Dynamic Type 最大字号。
15. iPhone SE 尺寸。

## 性能测试数据集

至少准备：

```text
50 works
500 works
1500 works
30-photo capture batch
30-photo Photos Picker import
Mac online
Mac offline
thumbnail missing
original-only legacy data
```

---

# 16. Codex 完成后的汇报格式

完成后请输出：

1. 修改的文件列表；
2. 每个问题的根因；
3. 每个问题的解决方式；
4. 数据迁移变化；
5. 图片管线变化；
6. Camera 生命周期变化；
7. Mac batch sync 变化；
8. 测试结果；
9. Instruments 前后对比；
10. 仍存在的风险。

性能对比至少使用下表：

```text
Metric                       Before     After
Cold first frame
Timeline interactive
Timeline scroll FPS
Gallery first visible image
Visited tab switch
Camera UI visible
Camera preview live - first
Camera preview live - second
Placement sheet visible
Batch review visible
Peak memory - 500 works
Main-thread stalls >100 ms
Mac refreshes - 30 captures
AI jobs - 30 captures
```

---

# 17. 最终产品要求

本轮不是单纯做一批 UI 微调。

完成后用户应明显感受到：

1. 打开 Volio，直接进入真正有价值的成长时间轴；
2. Timeline 两侧的记忆碎片更自然、更有生命力；
3. 第一次点击任何图片都不会布局失控；
4. 拍照、切页、滚动和弹窗都迅速响应；
5. 拍完一叠作品后，可以像翻照片一样横滑回看，再轻松放进时间轴；
6. App 在夜间不会突然出现不可读的白字；
7. 所有视觉效果建立在稳定、缓存和异步 I/O 之上，而不是增加新的性能负担。

不要以“动画看起来完成”作为验收标准。  
必须以真机 Release 性能、布局稳定性和完整拍摄闭环作为最终验收标准。
