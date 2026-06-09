import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'common.dart';

typedef ProxyGroupViewKeyMap =
    Map<String, GlobalObjectKey<_ProxyGroupViewState>>;

class ProxiesTabView extends ConsumerStatefulWidget {
  const ProxiesTabView({super.key});

  static Map<String, PageStorageKey> pageListStoreMap = {};

  @override
  ConsumerState<ProxiesTabView> createState() => ProxiesTabViewState();
}

class ProxiesTabViewState extends ConsumerState<ProxiesTabView>
    with TickerProviderStateMixin {
  TabController? _tabController;
  final _hasMoreButtonNotifier = ValueNotifier<bool>(false);
  ProxyGroupViewKeyMap _keyMap = {};

  @override
  void initState() {
    super.initState();
    ref.listenManual(proxiesTabControllerStateProvider, (prev, next) {
      if (prev == next) {
        return;
      }
      if (!stringListEquality.equals(prev?.a, next.a)) {
        _destroyTabController();
        final groupNames = next.a;
        final currentGroupName = next.b;
        final index = groupNames.indexWhere((item) => item == currentGroupName);
        _updateTabController(groupNames.length, index);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _destroyTabController();
    super.dispose();
  }

  void scrollToGroupSelected() {
    final currentGroupName = getCurrentGroupName();
    _keyMap[currentGroupName]?.currentState?.scrollToSelected();
  }

  DelayTestTask? startDelayTestCurrentGroup() {
    final group = _getCurrentGroup();
    if (group == null) return null;
    return delayTest(group.all, group.testUrl);
  }

  Group? _getCurrentGroup() {
    final groups = getCurrentGroups();
    if (groups.isEmpty) return null;

    final currentGroupName = getCurrentGroupName();
    if (currentGroupName != null) {
      final index = groups.indexWhere(
        (group) => group.name == currentGroupName,
      );
      if (index != -1) return groups[index];
    }

    final tabIndex = _tabController?.index;
    if (tabIndex != null && tabIndex >= 0 && tabIndex < groups.length) {
      return groups[tabIndex];
    }
    return groups.first;
  }

  Widget _buildMoreButton() {
    return Consumer(
      builder: (_, ref, _) {
        final isMobileView = ref.watch(isMobileViewProvider);
        return IconButton(
          onPressed: _showMoreMenu,
          icon: isMobileView
              ? const Icon(Icons.expand_more)
              : const Icon(Icons.chevron_right),
        );
      },
    );
  }

  void _showMoreMenu() {
    showSheet(
      context: context,
      props: const SheetProps(isScrollControlled: false),
      builder: (_) {
        return AdaptiveSheetScaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Consumer(
              builder: (_, ref, _) {
                final state = ref.watch(proxiesTabControllerStateProvider);
                final groupNames = state.a;
                final currentGroupName = state.b;
                return SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    runSpacing: 8,
                    spacing: 8,
                    children: [
                      for (final groupName in groupNames)
                        SettingTextCard(
                          groupName,
                          onPressed: () {
                            final index = groupNames.indexWhere(
                              (item) => item == groupName,
                            );
                            if (index == -1) return;
                            _tabController?.animateTo(index);
                            updateCurrentGroupName(groupName);
                            Navigator.of(context).pop();
                          },
                          isSelected: groupName == currentGroupName,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          title: context.appLocalizations.proxyGroup,
        );
      },
    );
  }

  void _tabControllerListener([int? index]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      int? groupIndex = index;
      if (groupIndex == -1) {
        return;
      }
      if (groupIndex == null) {
        final currentIndex = _tabController?.index;
        groupIndex = currentIndex;
      }
      final currentGroups = getCurrentGroups();
      if (groupIndex == null || groupIndex >= currentGroups.length) {
        return;
      }
      final currentGroup = currentGroups[groupIndex];
      updateCurrentGroupName(currentGroup.name);
    });
  }

  void _destroyTabController() {
    _tabController?.removeListener(_tabControllerListener);
    _tabController?.dispose();
    _tabController = null;
  }

  void _updateTabController(int length, int index) {
    _destroyTabController();
    if (length == 0) {
      return;
    }
    final realIndex = index == -1 ? 0 : index;
    _tabController ??= TabController(
      length: length,
      initialIndex: realIndex,
      vsync: this,
    );
    _tabControllerListener(realIndex);
    _tabController?.addListener(_tabControllerListener);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    ref.watch(themeSettingProvider.select((state) => state.textScale));
    final state = ref.watch(proxiesTabStateProvider.select((state) => state));
    final groups = state.groups;
    if (groups.isEmpty || _tabController == null) {
      return NullStatus(
        illustration: const ProxyEmptyIllustration(),
        label: appLocalizations.nullTip(appLocalizations.proxies),
      );
    }
    _keyMap = {};
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (scrollNotification) {
            _hasMoreButtonNotifier.value =
                scrollNotification.metrics.maxScrollExtent > 0;
            return false;
          },
          child: ValueListenableBuilder(
            valueListenable: _hasMoreButtonNotifier,
            builder: (_, value, child) {
              return Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  TabBar(
                    controller: _tabController,
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16 + (value ? 16 : 0),
                    ),
                    dividerColor: Colors.transparent,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    tabs: [
                      for (final group in groups)
                        Tab(
                          child: Builder(
                            builder: (context) {
                              return EmojiText(
                                group.name,
                                style: DefaultTextStyle.of(context).style,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  if (value) Positioned(right: 0, child: child!),
                ],
              );
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    context.colorScheme.surface.opacity10,
                    context.colorScheme.surface,
                  ],
                  stops: const [0.0, 0.1],
                ),
              ),
              child: _buildMoreButton(),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final group in groups)
                ProxyGroupView(
                  key: _keyMap.updateCacheValue(
                    group.name,
                    () => GlobalObjectKey<_ProxyGroupViewState>(group.name),
                  ),
                  group: group,
                  columns: state.columns,
                  cardType: state.proxyCardType,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProxyGroupView extends ConsumerStatefulWidget {
  final Group group;
  final int columns;
  final ProxyCardType cardType;

  const ProxyGroupView({
    super.key,
    required this.group,
    required this.columns,
    required this.cardType,
  });

  @override
  ConsumerState<ProxyGroupView> createState() => _ProxyGroupViewState();
}

class _ProxyGroupViewState extends ConsumerState<ProxyGroupView> {
  late final ScrollController _controller;

  List<Proxy> currentProxies = [];
  String? testUrl;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  PageStorageKey _getPageStorageKey() {
    final profile = globalState.container.read(currentProfileProvider);
    final key =
        '${profile?.id}_${ScrollPositionCacheKey.proxiesTabList.name}_${widget.group.name}';
    return ProxiesTabView.pageListStoreMap.updateCacheValue(
      key,
      () => PageStorageKey(key),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void scrollToSelected() {
    if (_controller.position.maxScrollExtent == 0) {
      return;
    }
    _controller.animateTo(
      min(
        16 +
            getScrollToSelectedOffset(
              groupName: widget.group.name,
              proxies: currentProxies,
            ),
        _controller.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final proxies = group.all;
    testUrl = group.testUrl;
    currentProxies = proxies;
    return CommonScrollBar(
      controller: _controller,
      child: GridView.builder(
        key: _getPageStorageKey(),
        controller: _controller,
        padding: const EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          bottom: 96,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: getItemHeight(widget.cardType),
        ),
        itemCount: currentProxies.length,
        itemBuilder: (_, index) {
          final proxy = currentProxies[index];
          return ProxyCard(
            testUrl: group.testUrl,
            groupType: group.type,
            type: widget.cardType,
            proxy: proxy,
            groupName: group.name,
          );
        },
      ),
    );
  }
}

class DelayTestButton extends StatefulWidget {
  final DelayTestTask? Function() onStart;

  const DelayTestButton({super.key, required this.onStart});

  @override
  State<DelayTestButton> createState() => _DelayTestButtonState();
}

class _DelayTestButtonState extends State<DelayTestButton> {
  DelayTestTask? _task;
  VoidCallback? _hideProgress;

  bool get _isTesting => _task?.isActive == true;

  bool get _isCancelling => _isTesting && _task?.isCancelled == true;

  void _cancelTask() {
    _task?.cancel();
    if (mounted) setState(() {});
  }

  Future<void> _handlePressed() async {
    if (_isTesting) {
      if (!_isCancelling) _cancelTask();
      return;
    }

    final task = widget.onStart();
    if (task == null) return;
    _showProgress(task);
    setState(() {
      _task = task;
    });
    try {
      await task.done;
    } finally {
      if (mounted && identical(_task, task)) {
        setState(() {
          _task = null;
        });
      }
      _hideProgress?.call();
      _hideProgress = null;
      task.dispose();
    }
  }

  void _showProgress(DelayTestTask task) {
    if (!task.shouldShowProgress) return;
    _hideProgress?.call();
    _hideProgress = context.showProgressNotifier(
      title: context.appLocalizations.delayTest,
      progress: task.progressNotifier,
      onCancel: _cancelTask,
    );
  }

  @override
  void dispose() {
    _hideProgress?.call();
    _task?.cancel();
    _task?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonFloatingActionButton(
      onPressed: _isCancelling ? null : _handlePressed,
      label: _isTesting ? appLocalizations.cancel : appLocalizations.delayTest,
      icon: Icon(_isTesting ? Icons.close : Icons.network_ping),
    );
  }
}
