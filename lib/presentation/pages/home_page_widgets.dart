part of 'home_page.dart';

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
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (total > 100) ...[
            const SizedBox(height: 4),
            Text(
              '结果较多，建议使用上方筛选条件缩小范围',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
              ),
            ),
          ],
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

    final placeholderColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: 64,
      height: 90,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: posterUrl == null || posterUrl.isEmpty
            ? Icon(Icons.movie_outlined, color: placeholderColor)
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
                  return Icon(
                    Icons.broken_image_outlined,
                    color: placeholderColor,
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
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (resource.year != null)
          Text(
            resource.year!,
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _resourceTypeColor(resource.type).withAlpha(26),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            _resourceTypeLabel(resource.type),
            style: TextStyle(
              fontSize: 10,
              color: _resourceTypeColor(resource.type),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (resource.episodeCount != null)
          Text(
            '共${resource.episodeCount}集',
            style: TextStyle(fontSize: 12, color: mutedColor),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  _MetaBadge(
                    label: _resourceTypeLabel(resource.type),
                    color: _resourceTypeColor(resource.type),
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
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
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
    this.action,
  }) : centered = false;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
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
