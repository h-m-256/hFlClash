import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

class ProxyCard extends StatelessWidget {
  final String groupName;
  final Proxy proxy;
  final GroupType groupType;
  final ProxyCardType type;
  final String? testUrl;

  const ProxyCard({
    super.key,
    required this.groupName,
    required this.testUrl,
    required this.proxy,
    required this.groupType,
    required this.type,
  });

  Measure get measure => globalState.measure;

  void _handleTestCurrentDelay() {
    proxyDelayTest(proxy, testUrl);
  }

  Widget _buildDelayText() {
    return SizedBox(
      height: measure.labelSmallHeight,
      child: Consumer(
        builder: (context, ref, _) {
          final delay = ref.watch(
            delayProvider(proxyName: proxy.name, testUrl: testUrl),
          );
          return FadeThroughBox(
            alignment: type == ProxyCardType.expand
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: delay == 0 || delay == null
                ? SizedBox(
                    height: measure.labelSmallHeight,
                    width: measure.labelSmallHeight,
                    child: delay == 0
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : IconButton(
                            icon: const Icon(Icons.bolt),
                            iconSize: globalState.measure.labelSmallHeight,
                            padding: EdgeInsets.zero,
                            onPressed: _handleTestCurrentDelay,
                          ),
                  )
                : GestureDetector(
                    onTap: _handleTestCurrentDelay,
                    child: Text(
                      delay > 0 ? '$delay ms' : 'Timeout',
                      style: context.textTheme.labelSmall?.copyWith(
                        overflow: TextOverflow.ellipsis,
                        color: utils.getDelayColor(delay),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildProxyNameText(BuildContext context) {
    if (type == ProxyCardType.min) {
      return SizedBox(
        height: measure.bodyMediumHeight * 1,
        child: EmojiText(
          proxy.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    } else {
      return SizedBox(
        height: measure.bodyMediumHeight * 2,
        child: EmojiText(
          proxy.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    }
  }

  Future<void> _changeProxy(WidgetRef ref) async {
    final isComputedSelected = groupType.isComputedSelected;
    final isSelector = groupType == GroupType.Selector;
    final ref = globalState.container;
    if (isComputedSelected || isSelector) {
      final currentProxyName = ref.read(proxyNameProvider(groupName));
      final nextProxyName = switch (isComputedSelected) {
        true => currentProxyName == proxy.name ? '' : proxy.name,
        false => proxy.name,
      };
      ref
          .read(profilesActionProvider.notifier)
          .updateCurrentSelectedMap(groupName, nextProxyName);
      ref
          .read(proxiesActionProvider.notifier)
          .changeProxyDebounce(groupName, nextProxyName);
      return;
    }
    globalState.showNotifier(currentAppLocalizations.notSelectedTip);
  }

  Future<void> _copyProxyLink(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      context.showNotifier(context.appLocalizations.copySuccess);
    }
  }

  void _toggleFavorite(WidgetRef ref) {
    ref.read(profilesActionProvider.notifier).toggleFavoriteProxy(proxy.name);
  }

  void _toggleProtectedFavorite(WidgetRef ref, String link) {
    ref
        .read(profilesActionProvider.notifier)
        .toggleProtectedFavoriteProxy(proxyName: proxy.name, link: link);
  }

  Widget _withProxyMenu({
    required BuildContext context,
    required Widget child,
  }) {
    return Consumer(
      builder: (context, ref, _) {
        final profile = ref.watch(currentProfileProvider);
        final link = profile?.proxyLinks[proxy.name];
        if (profile?.convertSubscription != true || link == null) return child;
        final isFavorite = profile!.favoriteProxyNames.contains(proxy.name);
        final isProtected = profile.protectedProxyLinks.containsKey(proxy.name);
        final appLocalizations = context.appLocalizations;
        return CommonPopupBox(
          targetBuilder: (open) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: () {
                open(offset: const Offset(0, 20));
              },
              child: child,
            );
          },
          popup: CommonPopupMenu(
            minWidth: 240,
            items: [
              PopupMenuItemData(
                icon: Icons.link,
                label: appLocalizations.copyLink,
                onPressed: () {
                  _copyProxyLink(context, link);
                },
              ),
              PopupMenuItemData(
                icon: isFavorite ? Icons.star_outline : Icons.star_rounded,
                label: isFavorite
                    ? appLocalizations.removeProxyFavorite
                    : appLocalizations.addProxyFavorite,
                onPressed: () {
                  _toggleFavorite(ref);
                },
              ),
              PopupMenuItemData(
                icon: isProtected
                    ? Icons.lock_open_rounded
                    : Icons.lock_rounded,
                label: isProtected
                    ? appLocalizations.removeProtectedProxyFavorite
                    : appLocalizations.addProtectedProxyFavorite,
                onPressed: () {
                  _toggleProtectedFavorite(ref, link);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final measure = globalState.measure;
    final delayText = _buildDelayText();
    final proxyNameText = _buildProxyNameText(context);
    final card = Stack(
      children: [
        Consumer(
          builder: (_, ref, child) {
            final selectedProxyName = ref.watch(
              selectedProxyNameProvider(groupName),
            );
            return CommonCard(
              key: key,
              onPressed: () {
                _changeProxy(ref);
              },
              isSelected: selectedProxyName == proxy.name,
              child: child!,
            );
          },
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                proxyNameText,
                const SizedBox(height: 8),
                if (type == ProxyCardType.expand) ...[
                  SizedBox(
                    height: measure.bodySmallHeight,
                    child: _ProxyDesc(proxy: proxy),
                  ),
                  const SizedBox(height: 6),
                  delayText,
                ] else
                  SizedBox(
                    height: measure.bodySmallHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          flex: 1,
                          child: TooltipText(
                            text: Text(
                              proxy.type,
                              style: context.textTheme.bodySmall?.copyWith(
                                overflow: TextOverflow.ellipsis,
                                color: context
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.opacity80,
                              ),
                            ),
                          ),
                        ),
                        delayText,
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (groupType.isComputedSelected)
          Positioned(
            top: 0,
            right: 0,
            child: _ProxyComputedMark(groupName: groupName, proxy: proxy),
          ),
        _ProxyFavoriteMark(proxy: proxy),
      ],
    );
    return _withProxyMenu(context: context, child: card);
  }
}

class _ProxyFavoriteMark extends ConsumerWidget {
  final Proxy proxy;

  const _ProxyFavoriteMark({required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(
      currentProfileProvider.select((profile) {
        return profile?.favoriteProxyNames.contains(proxy.name) == true ||
            profile?.protectedProxyLinks.containsKey(proxy.name) == true;
      }),
    );
    if (!isFavorite) return const SizedBox();
    return Positioned(
      top: 0,
      left: 0,
      child: Container(
        alignment: Alignment.topLeft,
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.colorScheme.secondaryContainer,
        ),
        child: Icon(
          Icons.star_rounded,
          size: 14,
          color: context.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ProxyDesc extends ConsumerWidget {
  final Proxy proxy;

  const _ProxyDesc({required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desc = ref.watch(proxyDescProvider(proxy));
    return EmojiText(
      desc,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.bodySmall?.copyWith(
        color: context.textTheme.bodySmall?.color?.opacity80,
      ),
    );
  }
}

class _ProxyComputedMark extends ConsumerWidget {
  final String groupName;
  final Proxy proxy;

  const _ProxyComputedMark({required this.groupName, required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyName = ref.watch(proxyNameProvider(groupName));
    if (proxyName != proxy.name) {
      return const SizedBox();
    }
    return Container(
      alignment: Alignment.topRight,
      margin: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.secondaryContainer,
        ),
        child: const SelectIcon(),
      ),
    );
  }
}
