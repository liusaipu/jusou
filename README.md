# Jusou 剧搜

Jusou（剧搜）是一个基于 Flutter 的多源资源搜索应用。它可以聚合本地索引、外部适配器和自定义 JSON 数据源，并在客户端完成链接识别、去重、排序、校验、收藏和历史记录管理。

## 功能

- 多来源搜索：支持本地索引、外部适配器和 `~/.jusou/sources/*.json` 自定义源。
- 链接识别：识别常见分享链接格式。
- 结果整理：按相关度、最新、多源可信度和文件大小排序，并支持来源、年份、类型、提取码和链接状态过滤。
- 去重合并：对同一分享链接或同一资源的多来源结果进行合并，保留更完整的海报、年份、大小和来源信息。
- 链接校验：检测链接格式、可访问状态和失效标记，缓存校验结果。
- 本地资料库：支持收藏、最近打开、搜索历史、失效反馈和外部源设置。
- 跨端运行：当前包含 macOS、Windows 和 Web 平台工程；发布包重点覆盖 macOS 和 Windows。

## 快速开始

```bash
flutter pub get
flutter run -d macos
```

如果需要运行 Web 版本：

```bash
flutter run -d chrome
```

## 数据源

Jusou 默认会读取当前用户目录下的本地数据：

```text
~/.jusou/index.json
~/.jusou/sources/*.json
```

`index.json` 和自定义 JSON 源中的资源字段会映射到 `Resource` 模型，常用字段包括：

```json
{
  "id": "resource-id",
  "title": "资源标题",
  "share_url": "https://example.com/share/example",
  "share_pwd": "abcd",
  "source": "local",
  "year": "2024",
  "type": "movie",
  "file_size": "12GB",
  "poster_url": "https://example.com/poster.jpg",
  "updated_at": "2026-01-01T00:00:00.000"
}
```

没有本地数据文件或远程地址时，应用会显示数据源引导。远程搜索地址可在应用设置中启用、停用或拖动排序。普通远程地址需要兼容 `/api/search?kw=关键词` JSON 接口；`alipansou.com` 会自动使用专用网页适配器，并解析站内跳转到真实阿里云盘链接。

## 配置导入导出

应用设置里可以导入或导出配置。导出时在保存窗口输入文件名，或选择已有 JSON 文件；如果重名，系统保存面板会先确认是否覆盖。导入时在打开窗口选择要导入的配置 JSON 文件。配置也可放在默认路径供 TG 爬虫读取：

```text
~/.jusou/config.json
```

配置包含远程搜索开关、远程搜索 URL 列表、深色模式和 Telegram 频道列表。配置包格式示例：

```json
{
  "app": "jusou",
  "schema_version": 1,
  "settings": {
    "enable_remote": true,
    "remote_urls": ["https://example.com"],
    "dark_mode": true,
    "telegram_channels": ["movie_channel"]
  }
}
```

## Crawler

`crawler/` 是独立的 Node.js 爬虫脚本目录，用于抓取或整理外部页面数据，输出到 `~/.jusou/index.json`，供应用作为本地索引读取。

```bash
cd crawler
npm install
node index.js
```

### TG 频道爬虫

Telegram 公开频道抓取已经内置到应用中（`lib/data/services/telegram_crawler.dart`）。在应用设置中维护 TG 频道列表后，从设置面板点击"运行 TG 爬虫"即可抓取，结果写入 `~/.jusou/sources/telegram.json`，下次搜索自动读取。频道列表与 `~/.jusou/config.json` 中的 `telegram_channels` 字段保持同步。

所有抓取结果视为不可信输入，链接校验/去重/排序管线会在搜索阶段统一处理。

## 验证

```bash
flutter analyze
flutter test
```

## 版本

当前发布版本为 `v1.0.2`，对应 Flutter 应用版本 `1.0.2+3`。
