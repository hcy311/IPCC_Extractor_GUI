# IPCC Extractor GUI

这是一个 macOS 图形工具，用来下载 IPSW、提取运营商配置、生成 IPCC，并按地区整理输出。

## 功能

- 原生 macOS 单窗口界面
- 尽量自动识别已连接 iPhone 的机型代号
- 查询最新正式版和 Beta 版本信息
- 支持手动选择本地 IPSW 文件
- 自动提取并整理 IPCC
- 自动开启 carrier testing
- 应用内安装或升级 `ipsw`
- 调用系统已安装的 `ipsw`，不把二进制硬塞进 app 包里

## 地区分类

- Mainland_China
- Hong_Kong
- Taiwan
- Japan
- Korea
- USA
- Canada
- Australia_NZ
- UK_Ireland
- Europe
- Other

## 文件说明

- `IPCC Extractor.app`: macOS 应用
- `IPCCExtractorApp.swift`: SwiftUI 源码
- `extract_all_ipcc.sh`: 核心提取脚本
- `extract_all_ipcc_zh.sh`: 中文入口脚本
- `extract_all_ipcc_en.sh`: 英文入口脚本
