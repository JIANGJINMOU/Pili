import 'package:flutter/painting.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/utils/storage_key.dart';

enum ShortVideoSubtitleLanguage with EnumWithLabel {
  auto('自动选择', ''),
  chinese('简体中文', 'zh'),
  english('英语', 'en'),
  japanese('日语', 'ja'),
  korean('韩语', 'ko'),
  french('法语', 'fr'),
  german('德语', 'de'),
  spanish('西班牙语', 'es');

  const ShortVideoSubtitleLanguage(this.label, this.code);
  @override
  final String label;
  final String code;
}

enum ShortVideoSubtitlePosition with EnumWithLabel {
  bottom('底部', Alignment.bottomCenter),
  center('居中', Alignment.center),
  top('顶部', Alignment.topCenter);

  const ShortVideoSubtitlePosition(this.label, this.alignment);
  @override
  final String label;
  final Alignment alignment;
}

enum ShortVideoSubtitleColor with EnumWithLabel {
  white('白色', Color(0xFFFFFFFF)),
  yellow('黄色', Color(0xFFFFE066)),
  cyan('青色', Color(0xFF80DEEA));

  const ShortVideoSubtitleColor(this.label, this.color);
  @override
  final String label;
  final Color color;
}

enum ShortVideoSubtitleAlign with EnumWithLabel {
  center('居中对齐', TextAlign.center),
  left('左对齐', TextAlign.left),
  right('右对齐', TextAlign.right);

  const ShortVideoSubtitleAlign(this.label, this.align);
  @override
  final String label;
  final TextAlign align;
}

enum ShortVideoSubtitleLines with EnumWithLabel {
  two('最多 2 行', 2),
  three('最多 3 行', 3),
  four('最多 4 行', 4),
  six('最多 6 行', 6);

  const ShortVideoSubtitleLines(this.label, this.count);
  @override
  final String label;
  final int count;
}

class ShortVideoSubtitlePreferences {
  const ShortVideoSubtitlePreferences({
    this.position = ShortVideoSubtitlePosition.bottom,
    this.color = ShortVideoSubtitleColor.white,
    this.align = ShortVideoSubtitleAlign.center,
    this.lines = ShortVideoSubtitleLines.three,
    this.bold = false,
    this.shadow = true,
    this.language = ShortVideoSubtitleLanguage.auto,
    this.translate = false,
    this.target = ShortVideoSubtitleLanguage.chinese,
    this.bilingual = true,
    this.fontSize = 16,
    this.backgroundOpacity = .65,
  });
  final ShortVideoSubtitleLanguage language, target;
  final bool translate, bilingual;
  final double fontSize, backgroundOpacity;
  final ShortVideoSubtitlePosition position;
  final ShortVideoSubtitleColor color;
  final ShortVideoSubtitleAlign align;
  final ShortVideoSubtitleLines lines;
  final bool bold, shadow;

  TextStyle get textStyle => TextStyle(
    color: color.color,
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    height: 1.35,
    shadows: shadow
        ? const [
            Shadow(
              color: Color(0xDD000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ]
        : null,
  );

  factory ShortVideoSubtitlePreferences.fromMap(Map<dynamic, dynamic> values) {
    ShortVideoSubtitleLanguage language(
      String key,
      ShortVideoSubtitleLanguage fallback,
    ) =>
        ShortVideoSubtitleLanguage.values
            .where((v) => v.name == values[key])
            .firstOrNull ??
        fallback;
    double number(String key, double fallback, double min, double max) {
      final value = values[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    final target = language(
      SettingBoxKey.shortVideoSubtitleTarget,
      ShortVideoSubtitleLanguage.chinese,
    );
    T choice<T extends Enum>(String key, List<T> options, T fallback) =>
        options.where((v) => v.name == values[key]).firstOrNull ?? fallback;
    return ShortVideoSubtitlePreferences(
      position: choice(
        SettingBoxKey.shortVideoSubtitlePosition,
        ShortVideoSubtitlePosition.values,
        ShortVideoSubtitlePosition.bottom,
      ),
      color: choice(
        SettingBoxKey.shortVideoSubtitleColor,
        ShortVideoSubtitleColor.values,
        ShortVideoSubtitleColor.white,
      ),
      align: choice(
        SettingBoxKey.shortVideoSubtitleAlign,
        ShortVideoSubtitleAlign.values,
        ShortVideoSubtitleAlign.center,
      ),
      lines: choice(
        SettingBoxKey.shortVideoSubtitleLines,
        ShortVideoSubtitleLines.values,
        ShortVideoSubtitleLines.three,
      ),
      bold: values[SettingBoxKey.shortVideoSubtitleBold] == true,
      shadow: values[SettingBoxKey.shortVideoSubtitleShadow] is bool
          ? values[SettingBoxKey.shortVideoSubtitleShadow] as bool
          : true,
      language: language(
        SettingBoxKey.shortVideoSubtitleLanguage,
        ShortVideoSubtitleLanguage.auto,
      ),
      // Removed portrait AI controls must not leave legacy translation active.
      translate: false,
      target: target == ShortVideoSubtitleLanguage.auto
          ? ShortVideoSubtitleLanguage.chinese
          : target,
      bilingual: values[SettingBoxKey.shortVideoSubtitleBilingual] is bool
          ? values[SettingBoxKey.shortVideoSubtitleBilingual] as bool
          : true,
      fontSize: number(SettingBoxKey.shortVideoSubtitleFont, 16, 12, 28),
      backgroundOpacity: number(
        SettingBoxKey.shortVideoSubtitleBackground,
        .65,
        0,
        .9,
      ),
    );
  }
}
