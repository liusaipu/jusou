import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/link_validation.dart';
import '../../data/models/local_library.dart';
import '../../data/models/resource.dart';
import '../../data/services/local_library_service.dart';
import '../../data/services/resource_key.dart';
import '../../data/services/resource_service.dart';
import '../../data/services/share_link_parser.dart';
import '../../main.dart';

part 'home_page_widgets.dart';
part 'home_page_helpers.dart';

const _allProviderKey = 'all';
const _allYearKey = 'all';
const _shareLinkParser = ShareLinkParser();
const _posterHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
  'Referer': 'https://www.alipan.com/',
};

enum _SortMode {
  relevance('相关度'),
  latest('最新'),
  multiSource('多源可信'),
  fileSize('文件大小');

  const _SortMode(this.label);

  final String label;
}

enum _TypeFilter {
  all('全部类型', null),
  movie('电影', 'movie'),
  tv('剧集', 'tv'),
  documentary('纪录片', 'documentary'),
  variety('综艺', 'variety');

  const _TypeFilter(this.label, this.value);

  final String label;
  final String? value;
}

enum _CodeFilter {
  all('提取码不限'),
  withCode('需要提取码'),
  withoutCode('无提取码');

  const _CodeFilter(this.label);

  final String label;
}

enum _ValidationFilter {
  all('校验不限'),
  verified('已识别'),
  reachable('可访问'),
  unchecked('未校验'),
  invalid('已失效');

  const _ValidationFilter(this.label);

  final String label;
}

const _configFileTypeGroup = XTypeGroup(
  label: 'JSON 配置文件',
  extensions: <String>['json'],
  mimeTypes: <String>['application/json'],
  uniformTypeIdentifiers: <String>['public.json'],
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _remoteUrlControllers = <TextEditingController>[];
  final _libraryService = LocalLibraryService();

  ResourceService _resourceService = ResourceService();
  int _searchGeneration = 0;

  List<Resource> _allResults = [];
  List<SourceStatus> _sourceStatuses = [];
  List<Resource> _favorites = [];
  List<Resource> _recentlyOpened = [];
  List<SearchHistoryEntry> _searchHistory = [];
  List<InvalidLinkReport> _invalidReports = [];
  LibrarySettings _settings = const LibrarySettings();

  String _selectedProvider = _allProviderKey;
  String _selectedYear = _allYearKey;
  _SortMode _sortMode = _SortMode.relevance;
  _TypeFilter _typeFilter = _TypeFilter.all;
  _CodeFilter _codeFilter = _CodeFilter.all;
  _ValidationFilter _validationFilter = _ValidationFilter.all;
  bool _onlyMergedSources = false;
  bool _isSearching = false;
  bool _isLoadingLibrary = true;
  String? _error;
  int _total = 0;
  int _totalBeforeDedupe = 0;
  int _elapsedMs = 0;
  final Set<String> _validatingLinks = {};

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final snapshot = await _libraryService.snapshot();
    if (!mounted) return;

    isDarkMode.value = snapshot.settings.darkMode;
    setState(() {
      _favorites = snapshot.favorites;
      _recentlyOpened = snapshot.recentlyOpened;
      _searchHistory = snapshot.searchHistory;
      _invalidReports = snapshot.invalidReports;
      _settings = snapshot.settings;
      for (final c in _remoteUrlControllers) {
        c.dispose();
      }
      _remoteUrlControllers.clear();
      for (final url in snapshot.settings.remoteUrls) {
        _remoteUrlControllers.add(TextEditingController(text: url));
      }
      if (_remoteUrlControllers.isEmpty) {
        _remoteUrlControllers.add(TextEditingController());
      }
      _resourceService = ResourceService(
        enableRemote: snapshot.settings.enableRemote,
        remoteUrls: snapshot.settings.remoteUrls,
      );
      _isLoadingLibrary = false;
    });
  }

  Future<void> _doSearch(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      _clearSearchResults();
      return;
    }

    final generation = ++_searchGeneration;
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final result = await _resourceService.searchDetailed(normalizedQuery);
      await _libraryService.cacheValidations(result.results);
      final cachedResults = await _libraryService.applyCachedValidation(
        result.results,
      );
      await _libraryService.recordSearch(normalizedQuery, result.total);
      final snapshot = await _libraryService.snapshot();

      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _allResults = cachedResults;
        _sourceStatuses = result.sourceStatuses;
        _total = result.total;
        _totalBeforeDedupe = result.totalBeforeDedupe;
        _elapsedMs = result.elapsedMs;
        _searchHistory = snapshot.searchHistory;
        _invalidReports = snapshot.invalidReports;
        _isSearching = false;
        _error = null;
        _normalizeActiveFilters();
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _error = e.toString();
        _isSearching = false;
      });
    }
  }

  void _clearSearchResults() {
    setState(() {
      _allResults = [];
      _sourceStatuses = [];
      _selectedProvider = _allProviderKey;
      _selectedYear = _allYearKey;
      _total = 0;
      _totalBeforeDedupe = 0;
      _elapsedMs = 0;
      _isSearching = false;
      _error = null;
    });
  }

  void _normalizeActiveFilters() {
    if (!_providerKeys(_allResults).contains(_selectedProvider)) {
      _selectedProvider = _allProviderKey;
    }
    if (_selectedYear != _allYearKey &&
        !_yearOptions().contains(_selectedYear)) {
      _selectedYear = _allYearKey;
    }
  }

  void _setQueryAndSearch(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );
    _doSearch(query);
  }

  Future<void> _openResource(Resource resource) async {
    final uri = Uri.tryParse(resource.shareUrl);
    if (uri == null || !uri.hasScheme) {
      _showSnack('链接格式无效');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    if (opened) {
      await _libraryService.recordOpened(resource);
      final snapshot = await _libraryService.snapshot();
      if (!mounted) return;
      setState(() {
        _recentlyOpened = snapshot.recentlyOpened;
      });
      _showSnack('已打开网盘链接');
      return;
    }

    _showSnack('无法打开链接');
  }

  Future<void> _copyLink(Resource resource) async {
    await Clipboard.setData(ClipboardData(text: resource.shareUrl));
    _showSnack('已复制链接');
  }

  Future<void> _copyCode(Resource resource) async {
    final code = resource.sharePwd?.trim();
    if (code == null || code.isEmpty) {
      _showSnack('没有提取码');
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));
    _showSnack('已复制提取码');
  }

  Future<void> _toggleThemeMode() async {
    final next = _settings.copyWith(darkMode: !isDarkMode.value);
    await _applySettings(next, refreshSearch: false);
  }

  Future<void> _toggleFavorite(Resource resource) async {
    final added = await _libraryService.toggleFavorite(resource);
    final snapshot = await _libraryService.snapshot();
    if (!mounted) return;

    setState(() {
      _favorites = snapshot.favorites;
    });
    _showSnack(added ? '已收藏' : '已取消收藏');
  }

  Future<void> _validateLink(Resource resource) async {
    final key = _resourceKey(resource);
    if (_validatingLinks.contains(key)) return;

    setState(() {
      _validatingLinks.add(key);
    });

    try {
      final updated = await _resourceService.validateLink(resource);
      await _libraryService.cacheValidation(updated);
      if (!mounted) return;

      setState(() {
        _replaceResource(updated);
        _validatingLinks.remove(key);
      });
      _showSnack(updated.validation?.reason ?? '链接校验完成');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validatingLinks.remove(key);
      });
      _showSnack('链接校验失败：$e');
    }
  }

  Future<void> _reportInvalid(Resource resource) async {
    final updated = resource.copyWith(
      validation: LinkValidationResult(
        level: LinkValidationLevel.invalid,
        reason: '用户标记失效',
        checkedAt: DateTime.now(),
      ),
    );
    await _libraryService.reportInvalid(updated);
    await _libraryService.cacheValidation(updated);
    final snapshot = await _libraryService.snapshot();
    if (!mounted) return;

    setState(() {
      _replaceResource(updated);
      _invalidReports = snapshot.invalidReports;
    });
    _showSnack('已标记失效');
  }

  void _replaceResource(Resource updated) {
    _allResults = _allResults.map((resource) {
      return _resourceKey(resource) == _resourceKey(updated)
          ? updated
          : resource;
    }).toList();
  }

  Future<void> _applySettings(
    LibrarySettings settings, {
    bool refreshSearch = true,
  }) async {
    await _libraryService.updateSettings(settings);
    var wroteConfigFile = false;
    try {
      await _libraryService.writeConfigFile(settings: settings);
      wroteConfigFile = true;
    } catch (_) {
      wroteConfigFile = false;
    }
    if (!mounted) return;

    isDarkMode.value = settings.darkMode;
    setState(() {
      _settings = settings;
      for (final c in _remoteUrlControllers) {
        c.dispose();
      }
      _remoteUrlControllers.clear();
      for (final url in settings.remoteUrls) {
        _remoteUrlControllers.add(TextEditingController(text: url));
      }
      if (_remoteUrlControllers.isEmpty) {
        _remoteUrlControllers.add(TextEditingController());
      }
      _resourceService = ResourceService(
        enableRemote: settings.enableRemote,
        remoteUrls: settings.remoteUrls,
      );
    });

    if (refreshSearch && _searchController.text.trim().isNotEmpty) {
      _doSearch(_searchController.text);
    }

    if (!wroteConfigFile) {
      _showSnack('设置已保存，配置文件写入失败');
    }
  }

  Future<void> _exportConfig() async {
    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: const <XTypeGroup>[_configFileTypeGroup],
        suggestedName: 'jusou-config.json',
        confirmButtonText: '导出',
        canCreateDirectories: true,
      );
      if (location == null) return;

      final file = await _libraryService.writeConfigFileAt(location.path);
      _showSnack('配置已导出到 ${file.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  Future<void> _importConfig() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_configFileTypeGroup],
        confirmButtonText: '导入',
      );
      if (file == null) return;

      final settings = await _libraryService.importConfigFile(file.path);
      await _applySettings(settings);
      _showSnack('配置已从 ${file.path} 导入');
    } catch (e) {
      _showSnack('导入失败：$e');
    }
  }

  Future<void> _openSettingsSheet() async {
    var enableRemote = _settings.enableRemote;
    final urlControllers = _remoteUrlControllers
        .map((c) => TextEditingController(text: c.text))
        .toList();
    final telegramController = TextEditingController(
      text: _settings.telegramChannels.join('\n'),
    );
    if (urlControllers.isEmpty) {
      urlControllers.add(TextEditingController());
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
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
                        value: enableRemote,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('远程搜索'),
                        onChanged: (value) {
                          setSheetState(() {
                            enableRemote = value;
                          });
                        },
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          itemCount: urlControllers.length,
                          onReorder: enableRemote
                              ? (oldIndex, newIndex) {
                                  setSheetState(() {
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    final controller = urlControllers.removeAt(
                                      oldIndex,
                                    );
                                    urlControllers.insert(newIndex, controller);
                                  });
                                }
                              : (_, _) {},
                          itemBuilder: (context, i) {
                            return Padding(
                              key: ValueKey(urlControllers[i]),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: i,
                                    enabled:
                                        enableRemote &&
                                        urlControllers.length > 1,
                                    child: Tooltip(
                                      message: '拖动调整顺序',
                                      child: Icon(
                                        Icons.drag_indicator,
                                        size: 20,
                                        color: enableRemote
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
                                      controller: urlControllers[i],
                                      enabled: enableRemote,
                                      decoration: InputDecoration(
                                        labelText: '远程搜索地址 ${i + 1}',
                                        prefixIcon: const Icon(
                                          Icons.link,
                                          size: 18,
                                        ),
                                        suffixIcon: urlControllers.length > 1
                                            ? IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                ),
                                                onPressed: enableRemote
                                                    ? () {
                                                        setSheetState(() {
                                                          final controller =
                                                              urlControllers
                                                                  .removeAt(i);
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
                      if (urlControllers.length < LibrarySettings.maxRemoteUrls)
                        TextButton.icon(
                          onPressed: enableRemote
                              ? () {
                                  setSheetState(() {
                                    urlControllers.add(TextEditingController());
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加备用地址'),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: telegramController,
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
                              final urls = urlControllers
                                  .map((c) => c.text.trim())
                                  .where((u) => u.isNotEmpty)
                                  .toList();
                              final next = LibrarySettings(
                                enableRemote: enableRemote,
                                remoteUrls: urls,
                                darkMode: _settings.darkMode,
                                telegramChannels: _parseTelegramChannels(
                                  telegramController.text,
                                ),
                              );
                              await _applySettings(next, refreshSearch: false);
                              if (!mounted) return;
                              navigator.pop();
                              if (_searchController.text.trim().isNotEmpty) {
                                _doSearch(_searchController.text);
                              }
                            },
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('保存'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              if (_searchController.text.trim().isNotEmpty) {
                                _doSearch(_searchController.text);
                              }
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('刷新本地索引'),
                          ),
                          TextButton.icon(
                            onPressed: _exportConfig,
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: const Text('导出配置'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _importConfig();
                            },
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text('导入配置'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await _libraryService.clearHistory();
                              await _loadLibrary();
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            icon: const Icon(
                              Icons.history_toggle_off,
                              size: 18,
                            ),
                            label: const Text('清空历史'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await _libraryService.clearRecentlyOpened();
                              await _loadLibrary();
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
                              size: 18,
                            ),
                            label: const Text('清空最近打开'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      for (final controller in urlControllers) {
        controller.dispose();
      }
      telegramController.dispose();
    }
  }

  void _showDetails(Resource resource) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _ResourceDetailSheet(
          resource: resource,
          isFavorite: _isFavorite(resource),
          isValidating: _validatingLinks.contains(_resourceKey(resource)),
          onOpen: () => _openResource(resource),
          onCopyLink: () => _copyLink(resource),
          onCopyCode: () => _copyCode(resource),
          onFavorite: () => _toggleFavorite(resource),
          onValidate: () => _validateLink(resource),
          onReportInvalid: () => _reportInvalid(resource),
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _remoteUrlControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            if (!_isSearching && _allResults.isNotEmpty) _buildFilterControls(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '搜电影、电视剧...',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onSubmitted: _doSearch,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '搜索',
            child: IconButton.filled(
              onPressed: _searchController.text.trim().isEmpty
                  ? null
                  : () => _doSearch(_searchController.text),
              icon: const Icon(Icons.arrow_forward, size: 20),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            Tooltip(
              message: '清空',
              child: IconButton(
                onPressed: () {
                  _searchController.clear();
                },
                icon: const Icon(Icons.close, size: 20),
              ),
            ),
          ValueListenableBuilder<bool>(
            valueListenable: isDarkMode,
            builder: (context, isDark, _) {
              return Tooltip(
                message: isDark ? '浅色模式' : '深色模式',
                child: IconButton(
                  onPressed: _toggleThemeMode,
                  icon: Icon(
                    isDark ? Icons.light_mode : Icons.dark_mode,
                    size: 20,
                  ),
                ),
              );
            },
          ),
          Tooltip(
            message: '设置',
            child: IconButton(
              onPressed: _openSettingsSheet,
              icon: const Icon(Icons.tune, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _CompactDropdown<_SortMode>(
            icon: Icons.sort,
            value: _sortMode,
            items: [
              for (final mode in _SortMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _sortMode = value;
              });
            },
          ),
          _CompactDropdown<String>(
            icon: Icons.cloud_queue,
            value: _selectedProvider,
            items: [
              for (final option in _providerFilterOptions())
                DropdownMenuItem(value: option.key, child: Text(option.label)),
            ],
            onChanged: (value) {
              setState(() {
                _selectedProvider = value ?? _allProviderKey;
              });
            },
          ),
          _CompactDropdown<_TypeFilter>(
            icon: Icons.category_outlined,
            value: _typeFilter,
            items: [
              for (final filter in _TypeFilter.values)
                DropdownMenuItem(value: filter, child: Text(filter.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _typeFilter = value;
              });
            },
          ),
          _CompactDropdown<String>(
            icon: Icons.calendar_month_outlined,
            value: _selectedYear,
            items: [
              const DropdownMenuItem(value: _allYearKey, child: Text('年份不限')),
              for (final year in _yearOptions())
                DropdownMenuItem(value: year, child: Text(year)),
            ],
            onChanged: (value) {
              setState(() {
                _selectedYear = value ?? _allYearKey;
              });
            },
          ),
          _CompactDropdown<_CodeFilter>(
            icon: Icons.key_outlined,
            value: _codeFilter,
            items: [
              for (final filter in _CodeFilter.values)
                DropdownMenuItem(value: filter, child: Text(filter.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _codeFilter = value;
              });
            },
          ),
          _CompactDropdown<_ValidationFilter>(
            icon: Icons.verified_outlined,
            value: _validationFilter,
            items: [
              for (final filter in _ValidationFilter.values)
                DropdownMenuItem(value: filter, child: Text(filter.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _validationFilter = value;
              });
            },
          ),
          FilterChip(
            selected: _onlyMergedSources,
            avatar: const Icon(Icons.merge_type, size: 18),
            label: const Text('多源合并'),
            onSelected: (value) {
              setState(() {
                _onlyMergedSources = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final results = _filteredResults();
    final hasConfiguredSources = _hasConfiguredSources;

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: '搜索失败',
        message: _error!,
        action: TextButton.icon(
          onPressed: () => _doSearch(_searchController.text),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('重试'),
        ),
      );
    }

    if (_allResults.isEmpty && _searchController.text.trim().isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          _MessageState.inline(
            icon: Icons.search_off,
            title: '未找到结果',
            message: hasConfiguredSources
                ? '可以换一个关键词，或在设置里调整远程搜索。'
                : '还没有可搜索的数据。请先导入 ~/.jusou/index.json，或在设置里添加远程搜索地址。',
            action: hasConfiguredSources
                ? null
                : TextButton.icon(
                    onPressed: _openSettingsSheet,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('设置'),
                  ),
          ),
          if (_sourceStatuses.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SourceStatusStrip(statuses: _sourceStatuses),
          ],
        ],
      );
    }

    if (_allResults.isEmpty) {
      return _buildDiscovery();
    }

    if (results.isEmpty) {
      return _MessageState(
        icon: Icons.filter_alt_off_outlined,
        title: '筛选后无结果',
        message: '调整网盘、年份、提取码或校验条件后再看。',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SearchSummary(
            visibleTotal: results.length,
            total: _total,
            totalBeforeDedupe: _totalBeforeDedupe,
            elapsedMs: _elapsedMs,
            isFiltered: results.length != _allResults.length,
            sourceStatuses: _sourceStatuses,
          );
        }

        final resource = results[index - 1];
        return _ResourceCard(
          resource: resource,
          isFavorite: _isFavorite(resource),
          isValidating: _validatingLinks.contains(_resourceKey(resource)),
          onTap: () => _showDetails(resource),
          onOpen: () => _openResource(resource),
          onCopyLink: () => _copyLink(resource),
          onCopyCode: () => _copyCode(resource),
          onFavorite: () => _toggleFavorite(resource),
          onValidate: () => _validateLink(resource),
          onReportInvalid: () => _reportInvalid(resource),
        );
      },
    );
  }

  Widget _buildDiscovery() {
    final categories = _resourceService
        .getCategories()
        .where((category) => category != '全部')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
      children: [
        const Icon(Icons.cloud_outlined, size: 48, color: Color(0xFF333333)),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            '搜索多来源网盘资源',
            style: TextStyle(color: Color(0xFF888888), fontSize: 14),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _discoverySubtitle(),
            style: const TextStyle(color: Color(0xFF555555), fontSize: 12),
          ),
        ),
        if (!_isLoadingLibrary && !_hasConfiguredSources) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _openSettingsSheet,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('添加远程搜索地址'),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              '也可以放入 ~/.jusou/index.json 或 ~/.jusou/sources/*.json',
              style: TextStyle(color: Color(0xFF777777), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final category in categories)
              ActionChip(
                avatar: const Icon(Icons.search, size: 16),
                label: Text(category),
                onPressed: () => _setQueryAndSearch(category),
              ),
          ],
        ),
        if (_searchHistory.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.history,
            title: '搜索历史',
            trailing: TextButton(
              onPressed: () async {
                await _libraryService.clearHistory();
                await _loadLibrary();
              },
              child: const Text('清空'),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _searchHistory.take(12))
                ActionChip(
                  label: Text('${item.query} · ${item.total}'),
                  onPressed: () => _setQueryAndSearch(item.query),
                ),
            ],
          ),
        ],
        if (_favorites.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.star_border, title: '收藏'),
          for (final resource in _favorites.take(5))
            _MiniResourceRow(
              resource: resource,
              onTap: () => _showDetails(resource),
              onOpen: () => _openResource(resource),
            ),
        ],
        if (_recentlyOpened.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.folder_open_outlined, title: '最近打开'),
          for (final resource in _recentlyOpened.take(5))
            _MiniResourceRow(
              resource: resource,
              onTap: () => _showDetails(resource),
              onOpen: () => _openResource(resource),
            ),
        ],
        if (_invalidReports.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.report_gmailerrorred, title: '失效反馈'),
          Text(
            '已记录 ${_invalidReports.length} 条',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
          ),
        ],
      ],
    );
  }

  List<Resource> _filteredResults() {
    final filtered = _allResults.where((resource) {
      if (_selectedProvider != _allProviderKey &&
          _providerKeyForResource(resource) != _selectedProvider) {
        return false;
      }
      if (_typeFilter.value != null && resource.type != _typeFilter.value) {
        return false;
      }
      if (_selectedYear != _allYearKey && resource.year != _selectedYear) {
        return false;
      }
      if (_codeFilter == _CodeFilter.withCode && !_hasShareCode(resource)) {
        return false;
      }
      if (_codeFilter == _CodeFilter.withoutCode && _hasShareCode(resource)) {
        return false;
      }
      if (_onlyMergedSources && resource.duplicateCount <= 1) {
        return false;
      }
      return _matchesValidationFilter(resource);
    }).toList();

    switch (_sortMode) {
      case _SortMode.relevance:
        return filtered;
      case _SortMode.latest:
        return filtered..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _SortMode.multiSource:
        return filtered..sort((a, b) {
          final duplicateCompare = b.duplicateCount.compareTo(a.duplicateCount);
          if (duplicateCompare != 0) return duplicateCompare;
          return b.qualityScore.compareTo(a.qualityScore);
        });
      case _SortMode.fileSize:
        return filtered
          ..sort((a, b) => _fileSizeBytes(b).compareTo(_fileSizeBytes(a)));
    }
  }

  bool _matchesValidationFilter(Resource resource) {
    final level = resource.validation?.level;
    return switch (_validationFilter) {
      _ValidationFilter.all => true,
      _ValidationFilter.verified =>
        level != null && level != LinkValidationLevel.invalid,
      _ValidationFilter.reachable =>
        level != null && level.score >= LinkValidationLevel.httpReachable.score,
      _ValidationFilter.unchecked => level == null,
      _ValidationFilter.invalid => level == LinkValidationLevel.invalid,
    };
  }

  List<_ProviderFilterOption> _providerFilterOptions() {
    final counts = <String, int>{};
    for (final resource in _allResults) {
      final provider = _providerKeyForResource(resource);
      counts[provider] = (counts[provider] ?? 0) + 1;
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final order = _providerSortIndex(
          a.key,
        ).compareTo(_providerSortIndex(b.key));
        if (order != 0) return order;
        return _providerLabel(a.key).compareTo(_providerLabel(b.key));
      });

    return [
      _ProviderFilterOption(
        key: _allProviderKey,
        label: '全部网盘（${_allResults.length}）',
      ),
      for (final entry in entries)
        _ProviderFilterOption(
          key: entry.key,
          label: '${_providerLabel(entry.key)}（${entry.value}）',
        ),
    ];
  }

  List<String> _yearOptions() {
    final years =
        _allResults
            .map((resource) => resource.year?.trim())
            .whereType<String>()
            .where((year) => year.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return years;
  }

  Set<String> _providerKeys(List<Resource> resources) {
    return {
      _allProviderKey,
      for (final resource in resources) _providerKeyForResource(resource),
    };
  }

  bool _isFavorite(Resource resource) {
    final key = _resourceKey(resource);
    return _favorites.any((item) => _resourceKey(item) == key);
  }

  bool get _hasConfiguredSources {
    return _resourceService.hasConfiguredDataSources;
  }

  String _discoverySubtitle() {
    if (_isLoadingLibrary) return '正在读取本地库';
    if (!_hasConfiguredSources) return '先添加数据源，再开始搜索';
    return '打开网盘链接或复制提取码';
  }
}
