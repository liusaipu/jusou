# Jusou v1.0.0

首个正式版本。macOS 桌面应用 + Windows 便携版。

## 变更

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
