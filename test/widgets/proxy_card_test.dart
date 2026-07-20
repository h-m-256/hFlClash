import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ProxyCard opens its menu from the card long press', (
    tester,
  ) async {
    const link =
        'vless://00000000-0000-0000-0000-000000000000@example.com:443'
        '?encryption=none&type=tcp#Node';
    final profile = Profile.normal(
      convertSubscription: true,
    ).copyWith(proxyLinks: {'Node': link});
    final container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => _TestProfiles([profile])),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _TestApp()),
    );

    final cardButton = tester.widget<OutlinedButton>(
      find.byType(OutlinedButton).first,
    );
    expect(cardButton.onLongPress, isNotNull);

    await tester.longPress(find.byType(OutlinedButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Add to favorites'), findsOneWidget);
  });

  testWidgets('ProxyCard keeps favorites menu without a source link', (
    tester,
  ) async {
    final profile = Profile.normal(convertSubscription: true);
    final container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => _TestProfiles([profile])),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _TestApp()),
    );
    await tester.longPress(find.byType(OutlinedButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
  });
}

class _TestProfiles extends Profiles {
  final List<Profile> initial;

  _TestProfiles(this.initial);

  @override
  List<Profile> build() => initial;

  @override
  void put(Profile profile) {
    state = [profile];
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      builder: (context, child) {
        globalState.theme = CommonTheme.of(context, 1);
        globalState.measure = Measure.of(context, 1);
        return child!;
      },
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            height: 100,
            child: ProxyCard(
              groupName: 'PROXY',
              testUrl: null,
              proxy: Proxy(name: 'Node', type: 'vless'),
              groupType: GroupType.Selector,
              type: ProxyCardType.min,
            ),
          ),
        ),
      ),
    );
  }
}
