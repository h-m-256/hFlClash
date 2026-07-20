import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight + 2;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight + measure.labelSmallHeight + 6,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

List<Group> getCurrentGroups() {
  return globalState.container.read(currentGroupsStateProvider).value;
}

List<Group> getGroups() {
  return globalState.container.read(groupsProvider);
}

String? getCurrentGroupName() {
  return globalState.container.read(
    currentProfileProvider.select((state) => state?.currentGroupName),
  );
}

void updateCurrentGroupName(String groupName) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentGroupName(groupName);
}

void updateCurrentUnfoldSet(Set<String> value) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentUnfoldSet(value);
}

Future<void> proxyDelayTest(
  Proxy proxy, [
  String? testUrl,
  DelayTestTask? task,
]) async {
  if (task?.isCancelled == true) return;
  final ref = globalState.container;
  final groups = getGroups();
  final selectedMap = ref.read(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  final state = computeRealSelectedProxyState(
    proxy.name,
    groups: groups,
    selectedMap: selectedMap,
  );
  final currentTestUrl = state.testUrl.takeFirstValid([
    ref.read(realTestUrlProvider(testUrl)),
  ]);
  if (state.proxyName.isEmpty) {
    return;
  }
  if (task?.isCancelled == true) return;
  if (task == null) {
    ref
        .read(proxiesActionProvider.notifier)
        .setDelay(Delay(url: currentTestUrl, name: state.proxyName, value: 0));
  }
  final delay = await coreController.getDelay(
    currentTestUrl,
    state.proxyName,
    testId: task?.id,
  );
  if (task?.isCancelled == true) return;
  ref.read(proxiesActionProvider.notifier).setDelay(delay);
}

DelayTestTask delayTest(List<Proxy> proxies, [String? testUrl]) {
  return DelayTestTask._(proxies, testUrl);
}

class DelayTestTask {
  final List<Proxy> proxies;
  final String? testUrl;
  final String id = utils.uuidV4;
  late final ValueNotifier<DelayTestProgress> progressNotifier = ValueNotifier(
    DelayTestProgress(completed: 0, total: proxies.length),
  );
  late final Future<bool> _startFuture = _startCoreTest();
  late final Future<void> done = _run();
  Future<void>? _cancelFuture;
  bool _isCancelled = false;
  bool _isCompleted = false;
  bool _disposeRequested = false;

  DelayTestTask._(this.proxies, this.testUrl);

  bool get isCancelled => _isCancelled;

  bool get isActive => !_isCompleted;

  int get total => proxies.length;

  bool get shouldShowProgress => total > 0;

  void cancel() {
    if (_isCancelled || _isCompleted) return;
    _isCancelled = true;
    progressNotifier.value = progressNotifier.value.copyWith(cancelled: true);
    _cancelFuture ??= _cancelCoreTest();
  }

  void dispose() {
    if (_disposeRequested) return;
    _disposeRequested = true;
    if (_isCompleted) {
      progressNotifier.dispose();
      return;
    }
    unawaited(
      done.then<void>(
        (_) => progressNotifier.dispose(),
        onError: (_, _) => progressNotifier.dispose(),
      ),
    );
  }

  void _increaseProgress() {
    final value = progressNotifier.value;
    progressNotifier.value = value.copyWith(
      completed: (value.completed + 1).clamp(0, value.total),
      cancelled: _isCancelled,
    );
  }

  Future<void> _run() async {
    var sessionStarted = false;
    try {
      if (proxies.isEmpty) return;
      sessionStarted = await _startFuture;
      if (!sessionStarted) return;
      if (_isCancelled) {
        await (_cancelFuture ??= _cancelCoreTest());
        return;
      }
      for (final batch in proxies.batch(100)) {
        if (_isCancelled) return;
        await Future.wait(
          batch.map((proxy) async {
            try {
              await proxyDelayTest(proxy, testUrl, this);
            } finally {
              _increaseProgress();
            }
          }),
        );
      }
      if (!_isCancelled) {
        globalState.container.read(sortNumProvider.notifier).add();
      }
    } finally {
      try {
        if (_isCancelled && sessionStarted) {
          await (_cancelFuture ??= _cancelCoreTest());
        }
        if (proxies.isNotEmpty) {
          await _finishCoreTest();
        }
      } finally {
        _isCompleted = true;
      }
    }
  }

  Future<bool> _startCoreTest() async {
    if (proxies.isEmpty) return false;
    try {
      return await coreController.startDelayTest(id);
    } catch (e) {
      commonPrint.log(
        'Failed to start delay test session: $e',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  Future<void> _cancelCoreTest() async {
    if (!await _startFuture) {
      await _finishCoreTest();
      return;
    }
    try {
      await coreController.cancelDelayTest(id);
    } catch (e) {
      commonPrint.log(
        'Failed to cancel delay test session: $e',
        logLevel: LogLevel.warning,
      );
      await _finishCoreTest();
    }
  }

  Future<void> _finishCoreTest() async {
    try {
      await coreController.finishDelayTest(id);
    } catch (e) {
      commonPrint.log(
        'Failed to finish delay test session: $e',
        logLevel: LogLevel.warning,
      );
    }
  }
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final ref = globalState.container;
  final columns = ref.read(proxiesColumnsProvider);
  final proxyCardType = ref.read(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  final selectedProxyName = ref.read(selectedProxyNameProvider(groupName));
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}
