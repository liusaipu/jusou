import 'package:flutter/material.dart';

import '../../data/models/local_library.dart';

class SettingsSheet extends StatefulWidget {
  final LibrarySettings initialSettings;
  final bool isCrawling;
  final Future<void> Function(LibrarySettings) onSave;
  final Future<void> Function() onExportConfig;
  final Future<void> Function() onImportConfig;
  final Future<void> Function() onClearHistory;
  final Future<void> Function() onClearRecentlyOpened;
  final Future<void> Function() onRunCrawler;

  const SettingsSheet({
    super.key,
    required this.initialSettings,
    required this.isCrawling,
    required this.onSave,
    required this.onExportConfig,
    required this.onImportConfig,
    required this.onClearHistory,
    required this.onClearRecentlyOpened,
    required this.onRunCrawler,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late bool _enableRemote;
  late final List<TextEditingController> _urlControllers;
  late final TextEditingController _telegramController;

  @override
  void initState() {
    super.initState();
    _enableRemote = widget.initialSettings.enableRemote;
    _urlControllers = [
      for (final url in widget.initialSettings.remoteUrls)
        TextEditingController(text: url),
    ];
    if (_urlControllers.isEmpty) {
      _urlControllers.add(TextEditingController());
    }
    _telegramController = TextEditingController(
      text: widget.initialSettings.telegramChannels.join('\n'),
    );
  }

  @override
  void dispose() {
    for (final controller in _urlControllers) {
      controller.dispose();
    }
    _telegramController.dispose();
    super.dispose();
  }

  LibrarySettings _collectSettings() {
    return LibrarySettings(
      enableRemote: _enableRemote,
      remoteUrls: _urlControllers
          .map((c) => c.text.trim())
          .where((u) => u.isNotEmpty)
          .toList(),
      darkMode: widget.initialSettings.darkMode,
      telegramChannels: _parseTelegramChannels(_telegramController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            SwitchListTile(
              value: _enableRemote,
              contentPadding: EdgeInsets.zero,
              title: const Text('远程搜索'),
              onChanged: (value) {
                setState(() {
                  _enableRemote = value;
                });
              },
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _urlControllers.length,
                onReorder: _enableRemote
                    ? (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final controller = _urlControllers.removeAt(oldIndex);
                          _urlControllers.insert(newIndex, controller);
                        });
                      }
                    : (_, _) {},
                itemBuilder: (context, i) {
                  return Padding(
                    key: ValueKey(_urlControllers[i]),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          enabled:
                              _enableRemote && _urlControllers.length > 1,
                          child: Tooltip(
                            message: '拖动调整顺序',
                            child: Icon(
                              Icons.drag_indicator,
                              size: 20,
                              color: _enableRemote
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant
                                  : Theme.of(context).disabledColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _urlControllers[i],
                            enabled: _enableRemote,
                            decoration: InputDecoration(
                              labelText: '远程搜索地址 ${i + 1}',
                              prefixIcon: const Icon(Icons.link, size: 18),
                              suffixIcon: _urlControllers.length > 1
                                  ? IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: _enableRemote
                                          ? () {
                                              setState(() {
                                                final controller =
                                                    _urlControllers.removeAt(i);
                                                controller.dispose();
                                              });
                                            }
                                          : null,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                proxyDecorator: (child, index, animation) {
                  return Material(
                    color: Colors.transparent,
                    child: FadeTransition(
                      opacity: animation.drive(
                        Tween<double>(begin: 0.92, end: 1),
                      ),
                      child: child,
                    ),
                  );
                },
              ),
            ),
            if (_urlControllers.length < LibrarySettings.maxRemoteUrls)
              TextButton.icon(
                onPressed: _enableRemote
                    ? () {
                        setState(() {
                          _urlControllers.add(TextEditingController());
                        });
                      }
                    : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加备用地址'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _telegramController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'TG 频道',
                hintText: '@channel 或 https://t.me/channel，每行一个',
                prefixIcon: Icon(Icons.forum_outlined, size: 18),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await widget.onSave(_collectSettings());
                    if (!mounted) return;
                    navigator.pop();
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('保存'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新本地索引'),
                ),
                TextButton.icon(
                  onPressed: widget.onExportConfig,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('导出配置'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onImportConfig();
                  },
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('导入配置'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await widget.onClearHistory();
                    if (!mounted) return;
                    navigator.pop();
                  },
                  icon: const Icon(Icons.history_toggle_off, size: 18),
                  label: const Text('清空历史'),
                ),
                TextButton.icon(
                  onPressed: widget.isCrawling
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          await widget.onRunCrawler();
                        },
                  icon: widget.isCrawling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.rss_feed_outlined, size: 18),
                  label: const Text('运行 TG 爬虫'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await widget.onClearRecentlyOpened();
                    if (!mounted) return;
                    navigator.pop();
                  },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空最近打开'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _parseTelegramChannels(String text) {
  final seen = <String>{};
  final channels = <String>[];
  for (final raw in text.split(RegExp(r'[\n,;]+'))) {
    var value = raw.trim();
    if (value.isEmpty) continue;
    value = value
        .replaceFirst(RegExp(r'^https?://t\.me/s/', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^https?://t\.me/', caseSensitive: false), '')
        .replaceFirst('@', '');
    value = value.split(RegExp(r'[/?#]')).first.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,}$').hasMatch(value)) continue;
    if (seen.add(value)) {
      channels.add(value);
      if (channels.length >= LibrarySettings.maxTelegramChannels) break;
    }
  }
  return channels;
}
