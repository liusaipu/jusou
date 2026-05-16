# Jusou

Jusou 是一个基于 Flutter 的多源网盘资源搜索应用，面向电影、剧集等资源检索场景。它可以聚合本地索引、PanSou 和自定义 JSON 数据源，并在客户端完成链接识别、去重、排序、校验、收藏和历史记录管理。

## 功能

- 多来源搜索：支持本地索引、PanSou API 和 `~/.jusou/sources/*.json` 自定义源。
- 网盘链接识别：识别阿里云盘、Alipan、UC、迅雷、115、123 云盘等常见分享链接。
- 结果整理：按相关度、最新、多源可信度和文件大小排序，并支持来源、年份、类型、提取码和链接状态过滤。
- 去重合并：对同一分享链接或同一资源的多来源结果进行合并，保留更完整的海报、年份、大小和来源信息。
- 链接校验：检测链接格式、可访问状态和失效标记，缓存校验结果。
- 本地资料库：支持收藏、最近打开、搜索历史、失效反馈和 PanSou 设置。
- 跨端运行：当前包含 macOS 和 Web 平台工程。

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
  "share_url": "https://www.alipan.com/s/example",
  "share_pwd": "abcd",
  "source": "local",
  "year": "2024",
  "type": "movie",
  "file_size": "12GB",
  "poster_url": "https://example.com/poster.jpg",
  "updated_at": "2026-01-01T00:00:00.000"
}
```

PanSou 默认开启，默认服务地址为 `https://so.252035.xyz`。也可以通过环境变量调整：

```bash
JUSOU_ENABLE_PANSOU=false flutter run -d macos
JUSOU_PANSOU_BASE_URL=https://example.com flutter run -d macos
```

应用内的设置面板也可以开关 PanSou 并修改 baseUrl。

## Crawler

`crawler/` 是独立的 Node.js 辅助脚本目录，用于抓取或整理外部资源数据：

```bash
cd crawler
npm install
node index.js
```

抓取结果和外部来源都应视为不可信输入，导入前建议清洗并校验字段。

## 验证

```bash
flutter analyze
flutter test
```

## 版本

当前首个发布版本为 `v0.9.8`，对应 Flutter 应用版本 `0.9.8+1`。
