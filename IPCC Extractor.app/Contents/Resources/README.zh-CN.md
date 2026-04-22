# IPCC Extractor GUI

**简体中文** | [English](README.md)

这是一个面向 macOS 的图形工具，用来下载或复用本地 IPSW、提取运营商配置、生成 `.ipcc` 文件，并按地区整理输出。

## 这个工具能做什么

IPCC Extractor 主要是把原本需要手动拼接的一整套流程做成 GUI：

- 下载 IPSW
- 或直接使用你已经有的本地 `.ipsw`
- 解包并提取 Carrier Bundles
- 生成全部 `.ipcc`
- 对常见运营商做更直观的重命名
- 按地区整理输出目录
- 自动开启 carrier testing
- 把完整日志保存到输出目录里
- 检查系统里的 `ipsw` 是否已安装、是否可能需要升级

## 为什么不把 `ipsw` 直接塞进 App

这个项目刻意不把 `ipsw` 二进制硬打包进 `.app`。

原因很直接：

- GUI 更新和 `ipsw` 更新可以解耦
- 后续维护更干净
- app 包体积更合理
- 出问题时更容易单独排查是 GUI 还是 `ipsw`

所以当前设计是：

- GUI 负责交互和流程编排
- 系统里安装的 `ipsw` 负责下载、查询和提取相关工作

## 运行要求

- macOS
- 系统可用的 `ipsw`
- 建议安装 Homebrew
- 需要足够的磁盘空间用于 IPSW 解包和中间文件

如果系统里没有 `ipsw`，app 会弹窗提示，并允许你在应用内直接安装或升级。

## `ipsw` 状态指示灯

界面里的 `ipsw` 区域会显示一个小圆点：

- 绿色：已安装，且 Homebrew 没有报告可用更新
- 黄色：已安装，但 Homebrew 报告有可用更新
- 红色：系统中未找到 `ipsw`
- 灰色：正在检测，或当前无法判断状态

## 固件版本查询

应用支持以下几种方式：

- 最新正式版
- 最新 Beta
- 指定版本号
- 指定构建号

如果你已经提前下载了 IPSW，也可以直接手动选择本地 `.ipsw`，跳过下载步骤。

## 设备输入方式

目前 GUI 只保留常用的有基带设备类别：

- `iPhone`
- `Cellular iPad`

你不需要再完整手打 `iPhone18,2` 这类代号，只需要输入后半段型号编号，例如：

- `18,2`
- `17,2`

应用会自动和设备类别拼接成：

- `iPhone18,2`
- `iPad17,2`

## 输出目录

默认情况下，app 会在 `.app` 同级目录下创建：

- `IPCC_Extractor`

你也可以在界面里手动选择输出目录。

生成后的 `.ipcc` 会按地区整理到类似下面这些文件夹中：

- `Mainland_China`
- `Hong_Kong`
- `Taiwan`
- `Japan`
- `Korea`
- `USA`
- `Canada`
- `Australia_NZ`
- `UK_Ireland`
- `Europe`
- `Other`

同时，app 会在输出目录里自动写入日志文件：

- `ipcc_extractor_YYYY-MM-DD_HH-mm-ss.log`

## 仓库结构

这个仓库现在尽量只保留 GUI 构建真正需要的部分：

- `IPCC Extractor.app`
- `IPCCExtractorApp.swift`
- `extract_all_ipcc.sh`

之前那些多语言包装脚本对于当前 GUI 版本已经不是必须，所以不再作为主要仓库内容保留。

## 构建方式

本地可以按类似下面的方式重新编译：

```bash
swiftc -parse-as-library IPCCExtractorApp.swift -o IPCC\ Extractor.app/Contents/MacOS/launcher
codesign --force --deep --sign - IPCC\ Extractor.app
```

并把最新的核心脚本同步到：

```text
IPCC Extractor.app/Contents/Resources/extract_all_ipcc.sh
```

## 典型使用流程

1. 打开 `IPCC Extractor.app`
2. 先确认界面里已经识别到系统 `ipsw`
3. 选择 `iPhone` 或 `Cellular iPad`
4. 输入型号编号
5. 选择下载模式，或者直接手动选本地 IPSW
6. 如果默认输出目录不合适，就手动换一个
7. 点击开始提取
8. 等待输出按地区整理好的 `.ipcc`，必要时查看日志

## 在 iPhone 上安装 IPCC

1. 用数据线把 iPhone 接到 Mac
2. 保持手机解锁，并信任这台电脑
3. 打开 Finder，在左侧点你的设备
4. 停留在 `General`
5. 按住 `Option`
6. 点击 `Check for Update...`
7. 选择 app 输出目录中的目标 `.ipcc`

## 排错建议

如果“最新正式版 / 最新 Beta”没有显示：

- 先确认设备代号是否正确
- 确认系统里的 `ipsw` 可以正常运行
- 确认网络正常
- 去输出目录里查看日志文件

如果 `ipsw` 状态看起来不对：

- 手动运行 `brew outdated ipsw --json=v2`
- 确认 Homebrew 能识别当前安装的 `ipsw`

如果提取失败：

- 先检查输出盘是否还有足够空间
- 可以改为手动选择本地 IPSW，再试一次
- 打开输出目录中的日志文件看具体报错
