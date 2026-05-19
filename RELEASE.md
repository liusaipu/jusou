# Jusou v1.0.2

图标与设置入口优化版本。macOS 桌面应用 + Windows 便携版。

## 变更

### 图标

- 更新 macOS Dock 图标，放大主体并减少四周留白
- 同步更新 Web 与 Windows 应用图标资源
- macOS `Info.plist` 显式使用 `AppIcon`

### 设置入口

- 移除首页右上角独立更多菜单，配置导入导出入口合并到设置面板
- 首页设置按钮文案统一为「设置」
- 未配置数据源时的空状态引导改为打开设置面板

### 配置

- 新增默认配置示例 `config/jusou-config.json`

## 安装

### macOS
下载 `Jusou-macos.dmg`，打开后将 Jusou 拖入 Applications 文件夹。首次提示「无法验证开发者」请在系统设置 → 隐私与安全性中点击「仍要打开」。

### Windows
下载 `Jusou-windows.zip`，解压后运行 `jusou.exe`。

## 数据源

默认读取 `~/.jusou/index.json` 和 `~/.jusou/sources/*.json`。远程搜索没有内置默认地址，可在应用设置中配置一个或多个地址。

## 校验

```
macOS:  <!-- shasum -a 256 Jusou-macos.dmg -->
Windows: <!-- certutil -hashfile Jusou-windows.zip SHA256 -->
```

<!--
v1.0.1 notes retained for context:

### 配置导入导出

- 新增配置导出保存窗口：用户可输入文件名或选择已有 JSON 文件
- 重名导出交给系统保存面板确认覆盖，避免重复弹窗
- 新增配置导入打开窗口：用户可直接选择指定 JSON 文件导入
- 配置包支持远程搜索开关、远程 URL 列表、深色模式和 Telegram 频道列表

### 设置与本地配置

- 深色/浅色模式设置会持久化保存
- 设置面板新增 Telegram 频道编辑
- 设置变更会同步写入 `~/.jusou/config.json`，供爬虫读取

### TG 爬虫

- TG 爬虫会合并读取 `crawler/channels.txt` 与 `~/.jusou/config.json`
- 自动发现频道后会同步回频道文件和配置文件

### 搜索与数据源

- 新增 `alipansou.com` 专用适配器，支持 JS Challenge 自动绕过和 HTML 结果解析
- 通用远程 JSON API 适配器增强：返回 HTML 时给出明确错误提示，不再静默解码为空
- 远程搜索源支持拖拽排序（最多 5 个），主源无结果时顺序 fallback
- 新增来源状态条，实时显示每个远程源的成功/空结果/部分失败/失败状态
- 链接校验支持 HEAD 降级 GET 自动回退
- 新增 `ResourceKey` 规范化链接身份，等价分享链接统一去重（如 aliyundrive.com 与 alipan.com）

### 筛选与排序

- 新增 4 种排序：相关度、最新、多源（按重复数）、文件大小
- 新增筛选维度：提取码（有/无/不限）、校验状态（已识别/可访问/未校验/已失效）、多源合并开关
- 网盘来源筛选显示各提供商结果数量

### UI 与交互

- 深色/浅色主题切换
- 应用标题改为「剧搜 / JUSOU」
- 首页拆分为 `home_page.dart` + `home_page_helpers.dart` + `home_page_widgets.dart`
- 搜索结果展示优化（年份、集数、文件大小、来源标签）
- 空状态引导：未配置数据源时提示导入本地索引或添加远程地址

### 数据与持久化

- 本地库持久化：收藏、最近打开、搜索历史、失效举报、校验缓存、设置
- 资源模型增强：支持 snake_case / camelCase JSON 双格式，类型归一化（电影/剧集/纪录片/综艺）

### 爬虫与工具

- 新增 `crawler/` 目录：通用站点爬虫 + TG 公开频道爬虫
- 支持从 Telegram 频道自动提取网盘分享链接

### 构建

- GitHub Actions 双平台 CI：推送 `v*` 标签自动构建并发布
- 更新 Flutter 版本至 3.41.9

## 安装

### macOS
下载 `Jusou-macos.dmg`，打开后将 Jusou 拖入 Applications 文件夹。首次提示「无法验证开发者」请在系统设置 → 隐私与安全性中点击「仍要打开」。

### Windows
下载 `Jusou-windows.zip`，解压后运行 `jusou.exe`。

## 数据源

默认读取 `~/.jusou/index.json` 和 `~/.jusou/sources/*.json`。远程搜索没有内置默认地址，可在应用设置中配置一个或多个地址。

## 校验

```
macOS:  <!-- shasum -a 256 Jusou-macos.dmg -->
Windows: <!-- certutil -hashfile Jusou-windows.zip SHA256 -->
```
-->
