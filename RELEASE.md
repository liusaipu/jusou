# Jusou v0.9.9

首个双平台正式版本：macOS 桌面应用 + Windows 便携版。

## 变更

- 深色/浅色主题切换
- 远程搜索支持多个备用数据源（最多 5 个），主源无结果时顺序 fallback
- 新增 Windows 平台支持
- GitHub Actions 双平台 CI：推送标签自动构建并发布
- 新增 TG 频道爬虫，自动发现社群频道
- 应用标题改为「剧搜 / JUSOU」
- 搜索结果显示优化

## 安装

### macOS
下载 `Jusou-macos.dmg`，打开后将 Jusou 拖入 Applications 文件夹。首次提示「无法验证开发者」请在系统设置 → 隐私与安全性中点击「仍要打开」。

### Windows
下载 `Jusou-windows.zip`，解压后运行 `jusou.exe`。

## 数据源

默认读取 `~/.jusou/index.json` 和 `~/.jusou/sources/*.json`。远程搜索数据源默认未启用，可在应用设置中配置地址。

## 校验

```
macOS:  <!-- shasum -a 256 Jusou-macos.dmg -->
Windows: <!-- certutil -hashfile Jusou-windows.zip SHA256 -->
```
