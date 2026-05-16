import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/link_validation.dart';
import '../../data/models/local_library.dart';
import '../../data/models/resource.dart';
import '../../data/services/local_library_service.dart';
import '../../data/services/resource_service.dart';
import '../../data/services/share_link_parser.dart';
import '../../main.dart';

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
  tv('剧集', 'tv');

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

  Future<void> _openSettingsSheet() async {
    var enableRemote = _settings.enableRemote;
    final urlControllers = _remoteUrlControllers
        .map((c) => TextEditingController(text: c.text))
        .toList();
    if (urlControllers.isEmpty) {
      urlControllers.add(TextEditingController());
    }

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '来源设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    ...List.generate(urlControllers.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: urlControllers[i],
                                enabled: enableRemote,
                                decoration: InputDecoration(
                                  labelText: '远程搜索地址 ${i + 1}',
                                  prefixIcon: const Icon(Icons.link, size: 18),
                                  suffixIcon: urlControllers.length > 1
                                      ? IconButton(
                                          icon: const Icon(Icons.close, size: 18),
                                          onPressed: enableRemote
                                              ? () {
                                                  setSheetState(() {
                                                    urlControllers.removeAt(i);
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
                    }),
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
                            );
                            await _libraryService.updateSettings(next);
                            if (!mounted) return;
                            setState(() {
                              _settings = next;
                              for (final c in _remoteUrlControllers) {
                                c.dispose();
                              }
                              _remoteUrlControllers.clear();
                              for (final url in urls) {
                                _remoteUrlControllers.add(TextEditingController(text: url));
                              }
                              if (_remoteUrlControllers.isEmpty) {
                                _remoteUrlControllers.add(TextEditingController());
                              }
                              _resourceService = ResourceService(
                                enableRemote: next.enableRemote,
                                remoteUrls: next.remoteUrls,
                              );
                            });
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
                          onPressed: () async {
                            await _libraryService.clearHistory();
                            await _loadLibrary();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                          icon: const Icon(Icons.history_toggle_off, size: 18),
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
                  onPressed: () => isDarkMode.value = !isDarkMode.value,
                  icon: Icon(
                    isDark ? Icons.light_mode : Icons.dark_mode,
                    size: 20,
                  ),
                ),
              );
            },
          ),
          Tooltip(
            message: '来源设置',
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
            message: '可以换一个关键词，或在来源设置里调整远程搜索。',
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
            _isLoadingLibrary ? '正在读取本地库' : '打开网盘链接或复制提取码',
            style: const TextStyle(color: Color(0xFF555555), fontSize: 12),
          ),
        ),
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
}

class _SearchSummary extends StatelessWidget {
  final int visibleTotal;
  final int total;
  final int totalBeforeDedupe;
  final int elapsedMs;
  final bool isFiltered;
  final List<SourceStatus> sourceStatuses;

  const _SearchSummary({
    required this.visibleTotal,
    required this.total,
    required this.totalBeforeDedupe,
    required this.elapsedMs,
    required this.isFiltered,
    required this.sourceStatuses,
  });

  @override
  Widget build(BuildContext context) {
    final countText = isFiltered
        ? '显示 $visibleTotal / $total 条结果'
        : '找到 $total 条结果';
    final dedupeText = totalBeforeDedupe > total
        ? ' · 去重前 $totalBeforeDedupe'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$countText$dedupeText · ${elapsedMs}ms',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
          ),
          if (sourceStatuses.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SourceStatusStrip(statuses: sourceStatuses),
          ],
        ],
      ),
    );
  }
}

class _SourceStatusStrip extends StatelessWidget {
  final List<SourceStatus> statuses;

  const _SourceStatusStrip({required this.statuses});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final status in statuses) ...[
            _SourceStatusChip(status: status),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _SourceStatusChip extends StatelessWidget {
  final SourceStatus status;

  const _SourceStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status.level) {
      SourceStatusLevel.success => const Color(0xFF00B51D),
      SourceStatusLevel.empty => const Color(0xFF888888),
      SourceStatusLevel.partialFailure => const Color(0xFFFFB000),
      SourceStatusLevel.failure => const Color(0xFFFF4D4F),
    };
    final suffix = switch (status.level) {
      SourceStatusLevel.success => '${status.resultCount}',
      SourceStatusLevel.empty => '0',
      SourceStatusLevel.partialFailure => '${status.resultCount} 部分失败',
      SourceStatusLevel.failure => '失败',
    };
    final label = '${status.sourceLabel} $suffix';

    return Tooltip(
      message: status.errorMessage ?? '${status.elapsedMs}ms',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _CompactDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 190),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outline.withAlpha(100)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isDense: true,
                  isExpanded: true,
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  final String? url;

  const _PosterTile({this.url});

  @override
  Widget build(BuildContext context) {
    final posterUrl = url?.trim();

    return SizedBox(
      width: 64,
      height: 90,
      child: ColoredBox(
        color: const Color(0xFF2A2A2A),
        child: posterUrl == null || posterUrl.isEmpty
            ? const Icon(Icons.movie_outlined, color: Color(0xFF555555))
            : CachedNetworkImage(
                imageUrl: posterUrl,
                httpHeaders: _posterHeaders,
                fit: BoxFit.cover,
                memCacheWidth: 128,
                memCacheHeight: 180,
                placeholder: (context, url) {
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  );
                },
                errorWidget: (context, url, error) {
                  return const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF555555),
                  );
                },
              ),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final Resource resource;
  final bool isFavorite;
  final bool isValidating;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onCopyLink;
  final VoidCallback onCopyCode;
  final VoidCallback onFavorite;
  final VoidCallback onValidate;
  final VoidCallback onReportInvalid;

  const _ResourceCard({
    required this.resource,
    required this.isFavorite,
    required this.isValidating,
    required this.onTap,
    required this.onOpen,
    required this.onCopyLink,
    required this.onCopyCode,
    required this.onFavorite,
    required this.onValidate,
    required this.onReportInvalid,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validation = resource.validation;
    final provider = _providerKeyForResource(resource);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _PosterTile(url: resource.posterUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            resource.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: isFavorite ? '取消收藏' : '收藏',
                          child: IconButton(
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: onFavorite,
                            icon: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              size: 19,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _ResourceMetaLine(resource: resource),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (resource.fileSize != null)
                          Text(
                            resource.fileSize!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF888888),
                            ),
                          ),
                        _MetaBadge(
                          label: _providerLabel(provider),
                          color: _providerColor(provider),
                        ),
                        if (resource.source.isNotEmpty)
                          _MetaBadge(
                            label: resource.source,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        if (validation != null)
                          _MetaBadge(
                            label: validation.level.label,
                            color: _validationColor(validation.level),
                          ),
                        if (resource.duplicateCount > 1)
                          _MetaBadge(
                            label: '${resource.duplicateCount}源合并',
                            color: const Color(0xFF00B51D),
                          ),
                        if (_hasShareCode(resource))
                          _MetaBadge(
                            label: '需提取码',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _ActionIconButton(
                          tooltip: '打开网盘链接',
                          icon: Icons.open_in_new,
                          onPressed: onOpen,
                        ),
                        _ActionIconButton(
                          tooltip: '复制链接',
                          icon: Icons.copy,
                          onPressed: onCopyLink,
                        ),
                        _ActionIconButton(
                          tooltip: '复制提取码',
                          icon: Icons.password,
                          onPressed: _hasShareCode(resource)
                              ? onCopyCode
                              : null,
                        ),
                        _ActionIconButton(
                          tooltip: '校验链接',
                          icon: Icons.verified_outlined,
                          isBusy: isValidating,
                          onPressed: isValidating ? null : onValidate,
                        ),
                        _ActionIconButton(
                          tooltip: '标记失效',
                          icon: Icons.report_gmailerrorred_outlined,
                          onPressed: onReportInvalid,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceMetaLine extends StatelessWidget {
  final Resource resource;

  const _ResourceMetaLine({required this.resource});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (resource.year != null)
          Text(
            resource.year!,
            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: resource.type == 'movie'
                ? const Color(0xFF1677FF).withAlpha(26)
                : const Color(0xFF00B51D).withAlpha(26),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            resource.type == 'movie' ? '电影' : '剧集',
            style: TextStyle(
              fontSize: 10,
              color: resource.type == 'movie'
                  ? const Color(0xFF1677FF)
                  : const Color(0xFF00B51D),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (resource.episodeCount != null)
          Text(
            '共${resource.episodeCount}集',
            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
      ],
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isBusy;

  const _ActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.outlined(
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: isBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : Icon(icon, size: 18),
      ),
    );
  }
}

class _ResourceDetailSheet extends StatelessWidget {
  final Resource resource;
  final bool isFavorite;
  final bool isValidating;
  final VoidCallback onOpen;
  final VoidCallback onCopyLink;
  final VoidCallback onCopyCode;
  final VoidCallback onFavorite;
  final VoidCallback onValidate;
  final VoidCallback onReportInvalid;

  const _ResourceDetailSheet({
    required this.resource,
    required this.isFavorite,
    required this.isValidating,
    required this.onOpen,
    required this.onCopyLink,
    required this.onCopyCode,
    required this.onFavorite,
    required this.onValidate,
    required this.onReportInvalid,
  });

  @override
  Widget build(BuildContext context) {
    final validation = resource.validation;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resource.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MetaBadge(
                    label: _providerLabel(_providerKeyForResource(resource)),
                    color: _providerColor(_providerKeyForResource(resource)),
                  ),
                  if (resource.year != null)
                    _MetaBadge(
                      label: resource.year!,
                      color: const Color(0xFF888888),
                    ),
                  _MetaBadge(
                    label: resource.type == 'movie' ? '电影' : '剧集',
                    color: resource.type == 'movie'
                        ? const Color(0xFF1677FF)
                        : const Color(0xFF00B51D),
                  ),
                  if (resource.fileSize != null)
                    _MetaBadge(
                      label: resource.fileSize!,
                      color: const Color(0xFF888888),
                    ),
                  if (resource.duplicateCount > 1)
                    _MetaBadge(
                      label: '${resource.duplicateCount}源合并',
                      color: const Color(0xFF00B51D),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailLabel(label: '分享链接', value: resource.shareUrl),
              if (_hasShareCode(resource))
                _DetailLabel(label: '提取码', value: resource.sharePwd!.trim()),
              if (resource.mergedSources.isNotEmpty)
                _DetailLabel(
                  label: '来源',
                  value: resource.mergedSources.join('、'),
                ),
              if (validation != null)
                _DetailLabel(
                  label: '校验',
                  value:
                      '${validation.level.label} · ${validation.reason} · ${_formatDateTime(validation.checkedAt)}',
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('打开网盘'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCopyLink,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('复制链接'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _hasShareCode(resource) ? onCopyCode : null,
                    icon: const Icon(Icons.password, size: 18),
                    label: const Text('复制提取码'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onFavorite,
                    icon: Icon(
                      isFavorite ? Icons.star : Icons.star_border,
                      size: 18,
                    ),
                    label: Text(isFavorite ? '取消收藏' : '收藏'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isValidating ? null : onValidate,
                    icon: isValidating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('校验'),
                  ),
                  TextButton.icon(
                    onPressed: onReportInvalid,
                    icon: const Icon(
                      Icons.report_gmailerrorred_outlined,
                      size: 18,
                    ),
                    label: const Text('标记失效'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLabel extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _MiniResourceRow extends StatelessWidget {
  final Resource resource;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  const _MiniResourceRow({
    required this.resource,
    required this.onTap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(resource.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (resource.year != null) resource.year,
          _providerLabel(_providerKeyForResource(resource)),
        ].whereType<String>().join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Tooltip(
        message: '打开网盘链接',
        child: IconButton(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new, size: 18),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF888888)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool centered;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  }) : centered = true;

  const _MessageState.inline({
    required this.icon,
    required this.title,
    required this.message,
  }) : action = null,
       centered = false;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 42, color: const Color(0xFF333333)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );

    if (!centered) return child;
    return Center(child: child);
  }
}

class _ProviderFilterOption {
  final String key;
  final String label;

  const _ProviderFilterOption({required this.key, required this.label});
}

class _MetaBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _providerKeyForResource(Resource resource) {
  final info = _shareLinkParser.parse(resource.shareUrl);
  return info.isRecognizedShare
      ? info.provider
      : ShareLinkParser.unknownProvider;
}

String _providerLabel(String provider) {
  return switch (provider) {
    'aliyun' => '阿里云盘',
    'baidu' => '百度网盘',
    'quark' => '夸克网盘',
    'uc' => 'UC网盘',
    'xunlei' => '迅雷云盘',
    '115' => '115网盘',
    '123' => '123云盘',
    _ => '其他网盘',
  };
}

int _providerSortIndex(String provider) {
  return switch (provider) {
    'aliyun' => 0,
    'baidu' => 1,
    'quark' => 2,
    'uc' => 3,
    'xunlei' => 4,
    '115' => 5,
    '123' => 6,
    _ => 99,
  };
}

Color _providerColor(String provider) {
  return switch (provider) {
    'aliyun' => const Color(0xFFFF6A00),
    'baidu' => const Color(0xFF315EFB),
    'quark' => const Color(0xFF00A3FF),
    'uc' => const Color(0xFFFFB000),
    'xunlei' => const Color(0xFF6A5CFF),
    '115' => const Color(0xFF00A870),
    '123' => const Color(0xFF1677FF),
    _ => const Color(0xFF888888),
  };
}

Color _validationColor(LinkValidationLevel level) {
  return switch (level) {
    LinkValidationLevel.invalid => const Color(0xFFFF4D4F),
    LinkValidationLevel.urlFormat => const Color(0xFF888888),
    LinkValidationLevel.recognizedShare => const Color(0xFF1677FF),
    LinkValidationLevel.httpReachable => const Color(0xFF00B51D),
    LinkValidationLevel.availableShare => const Color(0xFF00B51D),
    LinkValidationLevel.metadataReadable => const Color(0xFF00B51D),
  };
}

bool _hasShareCode(Resource resource) {
  return resource.sharePwd != null && resource.sharePwd!.trim().isNotEmpty;
}

String _resourceKey(Resource resource) {
  final shareUrl = resource.shareUrl.trim().toLowerCase();
  return shareUrl.isEmpty ? resource.id : shareUrl;
}

int _fileSizeBytes(Resource resource) {
  final text = resource.fileSize?.trim();
  if (text == null || text.isEmpty) return -1;

  final match = RegExp(
    r'(\d+(?:\.\d+)?)\s*(TB|GB|MB|KB|B)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return -1;

  final value = double.tryParse(match.group(1) ?? '');
  if (value == null) return -1;

  final unit = (match.group(2) ?? '').toUpperCase();
  final multiplier = switch (unit) {
    'TB' => 1024 * 1024 * 1024 * 1024,
    'GB' => 1024 * 1024 * 1024,
    'MB' => 1024 * 1024,
    'KB' => 1024,
    _ => 1,
  };
  return (value * multiplier).round();
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
