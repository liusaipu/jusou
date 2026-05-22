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
import '../../data/services/resource_filter_service.dart';
import '../../data/services/resource_key.dart';
import '../../data/services/resource_service.dart';
import '../../data/services/share_link_parser.dart';
import '../../data/services/telegram_crawler.dart';
import '../../main.dart';
import 'settings_sheet.dart';

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
  SortMode _sortMode = SortMode.relevance;
  TypeFilter _typeFilter = TypeFilter.all;
  CodeFilter _codeFilter = CodeFilter.all;
  ValidationFilter _validationFilter = ValidationFilter.all;
  bool _onlyMergedSources = false;
  bool _isSearching = false;
  bool _isLoadingLibrary = true;
  bool _isCrawling = false;
  String? _error;
  int _total = 0;
  int _totalBeforeDedupe = 0;
  int _elapsedMs = 0;
  final Set<String> _validatingLinks = {};
  Timer? _searchDebounceTimer;

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
      _resourceService = ResourceService(
        enableRemote: snapshot.settings.enableRemote,
        remoteUrls: snapshot.settings.remoteUrls,
      );
      _isLoadingLibrary = false;
    });

    _maybeAutoValidate();
  }

  Future<void> _maybeAutoValidate() async {
    if (!_libraryService.shouldAutoValidate()) return;

    final candidates = _libraryService.getCandidatesForAutoValidation();
    if (candidates.isEmpty) return;

    var validatedCount = 0;
    var invalidCount = 0;

    for (final resource in candidates) {
      try {
        final updated = await _resourceService.validateLink(
          resource,
          enableNetworkCheck: true,
        );
        await _libraryService.cacheValidation(updated);
        if (updated.validation?.level == LinkValidationLevel.invalid) {
          invalidCount++;
        }
        validatedCount++;
      } on Object {
        // 单条校验失败不影响整体流程
      }
    }

    await _libraryService.recordAutoValidation();

    if (!mounted) return;
    if (invalidCount > 0) {
      _showSnack('自动校验完成：$validatedCount 条中 $invalidCount 条已失效');
    } else if (validatedCount > 0) {
      _showSnack('自动校验完成：$validatedCount 条链接状态正常');
    }
  }

  Future<void> _runCrawler() async {
    final channels = _settings.telegramChannels;
    if (channels.isEmpty) {
      _showSnack('请先配置 Telegram 频道');
      return;
    }

    setState(() => _isCrawling = true);
    _showSnack('开始爬取 ${channels.length} 个频道...');

    try {
      final crawler = TelegramCrawler();
      final (newResources, newChannels, error) = await crawler.run(channels);

      if (!mounted) return;
      setState(() => _isCrawling = false);

      if (error != null) {
        _showSnack('爬取失败: $error');
        return;
      }

      _showSnack(
        '爬取完成: 新增 $newResources 条资源${newChannels > 0 ? ', 发现 $newChannels 个新频道' : ''}',
      );

      // 重新加载 ResourceService 以包含新数据
      _resourceService = ResourceService(
        enableRemote: _settings.enableRemote,
        remoteUrls: _settings.remoteUrls,
      );

      // 如果当前有搜索词，刷新结果
      if (_searchController.text.trim().isNotEmpty) {
        _doSearch(_searchController.text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCrawling = false);
      _showSnack('爬取异常: $e');
    }
  }

  void _debouncedSearch(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _doSearch(query);
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SettingsSheet(
          initialSettings: _settings,
          isCrawling: _isCrawling,
          onSave: (next) => _applySettings(next, refreshSearch: false),
          onExportConfig: _exportConfig,
          onImportConfig: _importConfig,
          onClearHistory: () async {
            await _libraryService.clearHistory();
            await _loadLibrary();
          },
          onClearRecentlyOpened: () async {
            await _libraryService.clearRecentlyOpened();
            await _loadLibrary();
          },
          onRunCrawler: _runCrawler,
        );
      },
    );
    if (!mounted) return;
    if (_searchController.text.trim().isNotEmpty) {
      _doSearch(_searchController.text);
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
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
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
              onSubmitted: _debouncedSearch,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '搜索',
            child: IconButton.filled(
              onPressed: _searchController.text.trim().isEmpty
                  ? null
                  : () => _debouncedSearch(_searchController.text),
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
          _CompactDropdown<SortMode>(
            icon: Icons.sort,
            value: _sortMode,
            items: [
              for (final mode in SortMode.values)
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
          _CompactDropdown<TypeFilter>(
            icon: Icons.category_outlined,
            value: _typeFilter,
            items: [
              for (final filter in TypeFilter.values)
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
          _CompactDropdown<CodeFilter>(
            icon: Icons.key_outlined,
            value: _codeFilter,
            items: [
              for (final filter in CodeFilter.values)
                DropdownMenuItem(value: filter, child: Text(filter.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _codeFilter = value;
              });
            },
          ),
          _CompactDropdown<ValidationFilter>(
            icon: Icons.verified_outlined,
            value: _validationFilter,
            items: [
              for (final filter in ValidationFilter.values)
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
        Icon(
          Icons.cloud_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '搜索多来源网盘资源',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _discoverySubtitle(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
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
          Center(
            child: Text(
              '也可以放入 ~/.jusou/index.json 或 ~/.jusou/sources/*.json',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  List<Resource> _filteredResults() {
    return const ResourceFilterService().apply(
      _allResults,
      FilterCriteria(
        provider: _selectedProvider,
        year: _selectedYear,
        sortMode: _sortMode,
        typeFilter: _typeFilter,
        codeFilter: _codeFilter,
        validationFilter: _validationFilter,
        onlyMergedSources: _onlyMergedSources,
      ),
    );
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
