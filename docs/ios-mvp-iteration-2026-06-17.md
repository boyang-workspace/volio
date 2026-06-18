# Volio iOS MVP 迭代记录

**日期**: 2026-06-17
**背景**: Volio iOS 由此前的「Mac 远程客户端」重构为「iPhone 本地优先，Mac 为可选助手」。
**核心改动文件**: 见下方分工。

---

## 为什么改

### 此前架构的问题

1. **配对门禁**：App 必须与 Mac Desktop 配对后才能使用，Mac 关机则 App 不可用
2. **复杂拍照流程**：Capture 页面需要先选孩子、选类型(Paper/Object)、选年龄模式、选日期，才能拍照
3. **图片不在手机本地**：所有图片加载自 Mac 的 URL，离线不可浏览
4. **功能臃肿**：AI 分析状态、队列信息、Then & Now 等超出 MVP 需求的功能占据主界面

### 新的设计原则

- **iPhone 是数据主库**，图片保存在 App 沙盒内
- **Mac 是可选的辅助设备**，只做 AI 分析和备份，原图不离开手机
- **Capture = 弹相机**，不预设任何条件
- **分享卡片是核心情绪价值**，不被 AI 等功能淹没

---

## 文件改动清单

### 新建文件 (4)

| 文件 | 作用 |
|------|------|
| `ImageStorage.swift` | 图片文件系统管理（保存原图、生成缩略图、删除作品） |
| `LocalWork.swift` | SwiftData 模型，定义作品本地数据结构 |
| `ShareCardView.swift` | 分享卡片功能（Gallery/Story 双模板） |
| `MacTypes.swift` | 保留旧 API 类型（Artwork、Child、PairingPayload 等），供以后 Mac Assist 复用 |

### 重写文件 (7)

| 文件 | 改动内容 |
|------|----------|
| `Models.swift` | `VolioSession` 从依赖 Mac API → 本地优先。删掉 `isPaired` 门禁、`refresh()`、`client` 等。新增 `createWork()`、`deleteWork()`、`toggleFavorite()`、`setup(modelContext:)`。新增 `LocalProfile` SwiftData 模型 |
| `VolioApp.swift` | 新增 SwiftData `modelContainer` 注入 |
| `ContentView.swift` | 不再检查配对/孩子。直接显示 `RootTabsView`。新增 Settings tab |
| `CaptureView.swift` | 从 700 行缩减到 ~300 行。去除 Paper/Object 选择、孩子选择、年龄选择、队列显示、批量上传。新流程：空状态 → 点击 Capture → 全屏相机 → Done → Review → Save All |
| `TimelineView.swift` | 从 373 行简化到 ~107 行。去除 header 渐变、StatPill、Then & Now、队列条、孩子切换。只保留按月分组的作品网格 |
| `ArtworkDetailView.swift` | 去除 AI 分析按钮、年龄段芯片、Work Type、孩子信息。保留大图 + 标题 + 日期 + Favorite + Share Card 入口 + 编辑 + 备注/引语 |
| `LibraryView.swift` | 改为使用 `LocalWork`。新增 Select 模式支持多选删除 |

### 保留文件 (不改)

| 文件 | 说明 |
|------|------|
| `VolioAPIClient.swift` | 保留供以后 Mac Assist 使用 |
| `PairingView.swift` | 保留 QR 扫描 + 配对逻辑，后续从 Settings 中进入 |
| `EditionView.swift` | 保留供以后使用 |
| `OnboardingView.swift` | 保留供以后使用 |
| `BatchRevealView.swift` | 保留供以后使用 |

---

## 关键架构决策

### 本地存储

```
Application Support / VolioLibrary /
  <work-uuid> /
    original.jpg     ← 拍照原始图片（JPEG 压缩 0.86）
    thumbnail.jpg    ← 600px 缩略图
```

SwiftData `LocalWork` 模型只存路径字符串，图片文件通过 `ImageStorage` 管理。

### VolioSession 职责变迁

```
此前：
VolioSession
├── isPaired gate
├── client → VolioAPI
├── refresh() → bootstrap()
├── artworks: [Artwork]
└── children: [Child]

现在：
VolioSession
├── works: [LocalWork]            ← 本地数据
├── createWork(data:)             ← 本地写入
├── deleteWork(work:)             ← 本地删除 + 文件清理
├── setup(modelContext:)          ← SwiftData 桥接
├── isMacPaired                   ← 可选 Mac Assist
├── baseURL / token               ← AppStorage 持久化
└── profile: LocalProfile         ← 可选创作者信息
```

### 图片流向

```
拍照 → UIImageJPEG → ImageStorage.saveOriginal()
                    → ImageStorage.generateThumbnail()
                    → LocalWork(originalPath, thumbnailPath)
                    → SwiftData insert()
```

浏览时 `LocalThumbnail` 通过 `file://` URL 加载本地图片。

### Mac Assist（可选，以后实现）

```
iPhone 生成 1200px 临时缩略图
→ 家庭 Wi-Fi 传到 Mac
→ Ollama 分析（标题/描述/标签/embedding）
→ 返回结果，iPhone 存入 LocalWork.aiDescription / aiTags
→ Mac 删除临时缩略图
```

原图永不离开 iPhone。

---

## 后续待办

- [ ] Mac Assist 联调（可推迟到 V2）
- [ ] Timeline 的分组优化（周/日层级，目前只有月）
- [ ] 分享卡片的自动背景色提取
- [ ] 纸张边缘检测（Vision 框架）
- [ ] iCloud 备份支持（可选）
- [ ] 从老版本迁移数据到本地存储
