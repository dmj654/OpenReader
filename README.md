# 开源阅读 · iOS 版

对标安卓 [「阅读」(Legado)](https://github.com/gedoor/legado) 的**纯本地 iOS 阅读器**，SwiftUI + UIKit（CoreText 排版）实现，**零第三方依赖**。

> 你正在看的这个仓库就是完整工程。它不会向你上传任何数据、没有广告、不请求多余权限。

---

## 目录

- [功能清单](#功能清单)
- [如何拿到 IPA（不需要 Mac）](#如何拿到-ipa不需要-mac)
- [签名与安装](#签名与安装)
- [有 Mac 的话怎么本地构建](#有-mac-的话怎么本地构建)
- [怎么把书加进来](#怎么把书加进来)
- [书源格式说明](#书源格式说明)
- [工程结构](#工程结构)
- [已知限制与 Roadmap](#已知限制与-roadmap)

---

## 功能清单

**本地阅读**
- TXT / EPUB 导入，自动探测 UTF-8 / UTF-16 / **GB18030(GBK)** / Big5 编码
- TXT 智能章节切分（`第x章` / `Chapter N` / `序章` / 数字编号 等规则）
- EPUB：OPF 元数据、NCX 目录、封面图、正文内图片
- CoreText 精确分页，阅读体验和系统图书一致
- 六套主题（纸白 / 米黄 / 羊皮 / 护眼 / 深灰 / 夜间）+ 跟随系统深色模式
- 字号 / 行距 / 段距 / 左右边距 / 首行缩进 / 五种字体全部可调
- 平移 / 仿真翻页两种动画，点击屏幕左右翻页
- 目录（支持搜索、正倒序）、进度条拖动跳转、断点续读
- 书签与阅读进度持久化，书架显示进度百分比
- 书内全文搜索（关键词高亮定位）
- 系统语音朗读（TTS），支持后台播放与连续翻页朗读
- 阅读时长统计、书籍详情页、分组、置顶、网格/列表双视图

**网络书源**
- 兼容 Legado 书源 JSON（字段：`bookSourceName` / `bookSourceUrl` / `searchUrl` / `ruleSearch` / `ruleToc` / `ruleContent`）
- 规则语法子集：`class.x` / `id.x` / `tag.div` / `.x` / `#x` / `@text` / `@html` / 属性名 / `[n]` / `##正则##替换` / `||` 备选
- 多书源并发搜索（取前 12 个启用书源），结果去重合并
- 一键加入书架、在线阅读正文

**系统集成**
- 「文件」App 完整可见（`UIFileSharingEnabled`），`Documents/Import` 作为投递箱
- 支持其他 App「用其他应用打开」（微信/浏览器下载的书直接传进来）
- 后台音频模式（朗读不中断）、屏幕常亮
- VoiceOver 无障碍标签、Dynamic Type、触觉反馈

---

## 如何拿到 IPA（不需要 Mac）

iPhone 的 App 必须在 macOS 上编译，这是苹果的硬性限制，Windows 上绕不过去。
解决办法是用 GitHub 免费提供的 macOS 云服务器（GitHub Actions）帮你编译，**全程 5 分钟、完全免费**。

### 第 1 步：把这份代码推到你的 GitHub 仓库

```bash
# 在本项目目录下
git init
git add .
git commit -m "init: 开源阅读 iOS 版"
git branch -M main
# 在 github.com 新建一个空仓库（比如叫 open-reader-ios），然后：
git remote add origin https://github.com/<你的用户名>/open-reader-ios.git
git push -u origin main
```

### 第 2 步：等云端打包

推送后 GitHub 会自动运行 `.github/workflows/build-ipa.yml`：

1. 打开你的仓库页面 → 顶部 **Actions** 标签
2. 点进正在运行的 **Build unsigned IPA** 工作流
3. 等 3~5 分钟，状态变绿 ✓

### 第 3 步：下载 IPA

还是在这次运行页面，拉到底部 **Artifacts** 区域，下载 **`OpenReader-unsigned-ipa`**，解压得到 `OpenReader-unsigned.ipa`。

> 以后想重新打包：改完代码 `git push` 即可；或者到 Actions 页面点 **Run workflow** 手动触发。

---

## 签名与安装

拿到的是**未签名 IPA**（苹果要求所有 App 必须有签名才能装）。用下面任意一种方式签：

### 方式 A：Sideloadly（Windows 最省事，推荐）

1. 电脑装 [iTunes](https://www.apple.com/itunes/)（提供驱动）和 [Sideloadly](https://sideloadly.io/)
2. iPhone 用数据线连电脑
3. 打开 Sideloadly → 拖入 `OpenReader-unsigned.ipa`
4. 填你的 Apple ID → **Start** → 几十秒后 iPhone 上出现「开源阅读」
5. iPhone 上：**设置 → 通用 → VPN与设备管理 → 信任你的开发者证书**

> 免费个人 Apple ID 签名 **7 天有效**，到期重复一次第 3~5 步即可（书架数据不受影响）。
> 99 美元/年的开发者账号签名可维持 1 年。

### 方式 B：AltStore（可自动续签，需要电脑偶尔在线）

装 [AltServer](https://altstore.io/)，iPhone 装 AltStore，把 ipa 发给 AltStore 安装。同一 Wi-Fi 下 AltServer 会自动帮你续签，不用每 7 天手动操作。

### 方式 C：爱思助手 / 牛蛙助手

直接把未签名 ipa 拖进爱思助手 →「安装（自签/正版签）」，流程同上。

---

## 有 Mac 的话怎么本地构建

本工程用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 描述工程，不提交 `.xcodeproj`：

```bash
brew install xcodegen
xcodegen generate          # 生成 OpenReader.xcodeproj
open OpenReader.xcodeproj
# Xcode 里选你的 iPhone → Cmd+R 直接跑
# 出包：Product → Archive → Distribute App
```

---

## 怎么把书加进来

三种方式任选：

| 方式 | 操作 |
|---|---|
| 书架内导入 | 书架右上角 **+** → 在「文件」App 里选 TXT / EPUB（支持多选） |
| 投递箱 | 「文件」App → **OpenReader** → **Import** 目录，把书拖进去，回书架**下拉刷新** |
| 其他 App 传书 | 微信/浏览器里下载的书 → 点开 → 「用其他应用打开」→ **开源阅读** |

---

## 书源格式说明

「书源」页右上角 **+**，粘贴 Legado 格式 JSON（数组或单个对象都行）：

```json
[
  {
    "bookSourceName": "示例书源",
    "bookSourceUrl": "https://example.com",
    "enabled": true,
    "searchUrl": "https://example.com/search?q={{key}}&p={{page}}",
    "ruleSearch": {
      "bookList": "class.result@tag.item",
      "name": "tag.h3@text",
      "author": "class.author@text",
      "bookUrl": "tag.a.0@href",
      "coverUrl": "tag.img@src"
    },
    "ruleToc": {
      "chapterList": "class.chapter-list@tag.li",
      "chapterName": "tag.a@text",
      "chapterUrl": "tag.a@href"
    },
    "ruleContent": { "content": "id.content@html" }
  }
]
```

规则速查（支持的是 Legado 的**子集**）：

| 写法 | 含义 |
|---|---|
| `class.x` / `.x` | 取 class 含 `x` 的所有后代节点 |
| `id.x` / `#x` | 取 id 为 `x` 的后代节点 |
| `tag.div` / `div` | 取标签为 div 的后代节点 |
| `children` | 直接子节点 |
| `tag.li[0]` / `[last]` | 按下标取 |
| `@text` | 节点全部文本 |
| `@ownText` | 仅自身文本（不含子节点） |
| `@html` / `@outerhtml` | 内/外 HTML |
| `@href` `@src` `@title`… | 任意属性值 |
| `规则##正则##替换` | 结果正则替换 |
| `规则A\|\|规则B` | A 取不到就用 B |
| `{{key}}` `{{page}}` | 搜索 URL 占位符 |

> 没写 `ruleToc.chapterList` 时会自动把页面里所有 `<a>` 当章节目录兜底。

---

## 工程结构

```
├── project.yml                     # XcodeGen 工程描述（唯一事实来源）
├── .github/workflows/build-ipa.yml # 云打包流水线 → 未签名 ipa
├── scripts/make_icon.py            # 纯标准库生成 App 图标
└── OpenReader/
    ├── App/        入口、TabView、环境注入
    ├── Common/     主题色板、扩展、触觉反馈
    ├── Models/     Book / Chapter / Bookmark / BookSource
    ├── Storage/    FileStore 路径、LibraryStore 仓库、阅读设置
    ├── Parsing/    编码探测、章节切分、ZIP、EPUB、导入
    ├── Reader/     CoreText 分页引擎、翻页容器、菜单、面板、TTS
    ├── Library/    书架、详情页、导入协调器
    ├── Sources/    HTML 解析 + 规则求值 + 书源引擎与界面
    └── Settings/   全局设置、关于
```

技术要点：
- **分页**：`CTFramesetter` 对每章做整章排版后按页面尺寸切片，缓存按「排版签名」失效（换主题零成本重绘，换字号才重排）
- **翻页**：`UIPageViewController` + 自绘 `UIView`（`CTFrameDraw`），点击分区用 `UITapGestureRecognizer` 三分屏
- **颜色与排版解耦**：排版字符串里不带前景色，绘制时统一 `setFill`，夜间模式切换即时生效
- **EPUB 图片**：解包到沙盒，渲染时内联为 `data:` URI 交给系统 HTML 导入器，规避 WebView 加载沙盒文件的不确定性
- **ZIP**：手写只读解析器（stored + deflate + Zip64），inflate 走系统 `Compression` 框架并按预期大小双路校验

---

## 已知限制与 Roadmap

- [ ] EPUB 里的 SVG 图片暂不渲染
- [ ] 书源规则暂不支持 JS 混淆 / `@js:` 脚本规则 / WebView 解析类书源（这类源需要内嵌 JS 引擎）
- [ ] 暂不支持 PDF、Mobi、Azw3
- [ ] 暂无 WebDAV 备份 / 换设备同步
- [ ] 划线笔记目前只有列表展示，无导出
- [ ] 无 PDF 重排、无字典查询

欢迎按上面结构加功能——每个模块都是独立的，改起来互不影响。
