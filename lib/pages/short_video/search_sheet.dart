import 'package:PiliPlus/models/common/search/video_search_type.dart';
import 'package:PiliPlus/pages/short_video/launch.dart';
import 'package:PiliPlus/pages/short_video/search_feed.dart';
import 'package:material_ui/material_ui.dart';

class ShortVideoSearchSheet extends StatefulWidget {
  const ShortVideoSearchSheet({
    super.key,
    this.initialQuery = '',
    this.feedFactory = ShortVideoSearchFeed.new,
  });
  final String initialQuery;
  final ShortVideoSearchFeed Function(String) feedFactory;
  @override
  State<ShortVideoSearchSheet> createState() => _ShortVideoSearchSheetState();
}

class _ShortVideoSearchSheetState extends State<ShortVideoSearchSheet> {
  late final _text = TextEditingController(text: widget.initialQuery);
  ShortVideoSearchFeed? _feed;
  bool _busy = false;
  bool _continueSearch = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _resetResults() => setState(() {
    _feed = null;
    _error = null;
    _continueSearch = false;
  });

  void _selectQuery(String query) {
    _text.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _resetResults();
  }

  Future<void> _submit() async {
    final query = _text.text.trim();
    if (_busy || query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _continueSearch = false;
    });
    final feed = _feed?.query == query ? _feed! : widget.feedFactory(query);
    _feed = feed;
    try {
      final items = await feed.load();
      if (!mounted) return;
      if (items.isNotEmpty) {
        Navigator.of(context).pop(
          ShortVideoLaunch(
            item: items.first,
            searchFeed: feed,
            searchItems: items,
          ),
        );
      } else {
        setState(() {
          _continueSearch = !feed.ended;
          _error = feed.ended ? '没有找到标题或标签匹配的视频，试试其他关键词' : '这批结果暂无匹配，可以继续查找';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '搜索失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height:
              (media.size.height -
                  media.viewInsets.bottom -
                  media.padding.top) *
              .9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('竖屏搜索', style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: '关闭搜索',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _text,
                        enabled: !_busy,
                        maxLength: 100,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: '视频标题或标签',
                          hintText: '搜点感兴趣的内容',
                          counterText: '',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _text.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空关键词',
                                  onPressed: _busy
                                      ? null
                                      : () => _selectQuery(''),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onChanged: (_) => _resetResults(),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '从首个结果开始播放，上下滑动继续看相关视频',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text('分区快捷词', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('点选填入关键词，也可以自由编辑', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final zone in VideoZoneType.values)
                            if (zone != VideoZoneType.all)
                              ChoiceChip(
                                label: Text(zone.label),
                                selected: _text.text.trim() == zone.label,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                                visualDensity: VisualDensity.standard,
                                onSelected: _busy
                                    ? null
                                    : (_) => _selectQuery(zone.label),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton.icon(
                  onPressed: _busy || _text.text.trim().isEmpty
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _busy
                        ? '正在搜索…'
                        : _continueSearch
                        ? '继续查找'
                        : '搜索并播放',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
