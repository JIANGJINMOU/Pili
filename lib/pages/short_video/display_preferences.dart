import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:flutter/painting.dart';

enum ShortVideoAspect with EnumWithLabel {
  original('原始比例', null),
  wide('16:9', 16 / 9),
  classic('4:3', 4 / 3),
  square('1:1', 1),
  portrait('9:16', 9 / 16);

  const ShortVideoAspect(this.label, this.ratio);
  @override
  final String label;
  final double? ratio;
}

enum ShortVideoFit with EnumWithLabel {
  contain('完整显示（默认）', BoxFit.contain),
  cover('铺满裁切', BoxFit.cover),
  fill('拉伸铺满', BoxFit.fill);

  const ShortVideoFit(this.label, this.fit);
  @override
  final String label;
  final BoxFit fit;
}
