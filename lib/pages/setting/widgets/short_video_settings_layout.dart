import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/short_video_settings.dart';
import 'package:material_ui/material_ui.dart';

/// Keep the searchable setting models shared; only the portrait page is grouped.
class ShortVideoSettingsLayout extends StatelessWidget {
  const ShortVideoSettingsLayout({
    super.key,
    required this.settings,
    required this.padding,
  });
  final List<SettingsModel> settings;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    var group = <Widget>[];
    void flush() {
      if (group.isEmpty) return;
      children.add(
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: group),
        ),
      );
      group = [];
    }

    for (final model in settings) {
      if (model is WidgetModel && model.child is ShortVideoSettingSection) {
        flush();
        children.add(model.widget);
      } else {
        group.add(model.widget);
      }
    }
    flush();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        padding.left + 12,
        8,
        padding.right + 12,
        padding.bottom + 40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
