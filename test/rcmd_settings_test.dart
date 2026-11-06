import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/rcmd_mode.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class PendingFeed extends RcmdController {
  final requests = <Completer<LoadingState>>[];

  @override
  Future<LoadingState> customGetData() {
    final request = Completer<LoadingState>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-rcmd-settings-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  setUp(() => GStorage.setting.clear());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'upstream source indices migrate without changing their meaning',
    () async {
      for (final (index, expected) in [
        (0, RcmdMode.app),
        (1, RcmdMode.web),
        (2, RcmdMode.desktop),
      ]) {
        await GStorage.setting.put(SettingBoxKey.rcmdSource, index);
        expect(Pref.rcmdMode, expected);
      }
      await GStorage.setting.put(SettingBoxKey.rcmdMode, RcmdMode.merged.index);
      expect(Pref.rcmdMode, RcmdMode.merged);
      expect(RcmdMode.desktop.hasAppSource, isFalse);
      expect(RcmdMode.merged.hasAppSource, isTrue);
    },
  );

  test(
    'source reload waits for an earlier query and issues a fresh request',
    () async {
      final controller = PendingFeed();
      final first = controller.queryData();
      controller.rcmdMode = RcmdMode.desktop;
      final reload = controller.onReload();
      expect(controller.requests, hasLength(1));
      controller.requests.first.complete(const Success([]));
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(controller.requests, hasLength(2));
      controller.requests.last.complete(const Success([]));
      await reload;
      expect(controller.isLoading, isFalse);
      expect(controller.loadingState.value, isA<Success>());
      controller.onClose();
    },
  );
}
