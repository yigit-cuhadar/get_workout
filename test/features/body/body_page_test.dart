import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/featured_card.dart';
import 'package:get_workout/features/body/domain/body_chart.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/entry_body_fat.dart';
import 'package:get_workout/features/body/domain/measurement_summary.dart';
import 'package:get_workout/features/body/presentation/body_chart_cubit.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/body/presentation/body_page.dart';
import 'package:get_workout/features/body/presentation/measurement_summary_cubit.dart';
import 'package:get_workout/features/body/presentation/measurement_summary_page.dart';
import 'package:get_workout/features/body/presentation/weight_form_cubit.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _BodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

class _ChartCubit extends MockCubit<BodyChartState> implements BodyChartCubit {}

class _SummaryCubit extends MockCubit<MeasurementSummaryState>
    implements MeasurementSummaryCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _ProfileCubit extends MockCubit<ProfileState> implements ProfileCubit {}

class _WeightFormCubit extends MockCubit<WeightFormState>
    implements WeightFormCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

void main() {
  final year = DateTime.now().year;
  // Measurement days on Oct 18 and Nov 1, weigh-ins on Nov 10 and 13.
  final oct18 = BodyEntry(
    id: 'oct18',
    date: DateTime(year, 10, 18, 8),
    weightKg: 84.1,
    measurements: const {
      BodyMeasurement.waist: 92,
      BodyMeasurement.leftUpperArm: 36,
      BodyMeasurement.rightUpperArm: 35.5,
    },
    photos: const {PhotoPose.front: 'front-1.jpg'},
  );
  final nov1 = BodyEntry(
    id: 'nov1',
    date: DateTime(year, 11, 1, 8),
    weightKg: 82.9,
    measurements: const {
      BodyMeasurement.waist: 88.5,
      BodyMeasurement.leftUpperArm: 36.5,
      BodyMeasurement.rightUpperArm: 35.8,
    },
  );
  final nov10 = BodyEntry(
    id: 'nov10',
    date: DateTime(year, 11, 10, 7),
    weightKg: 82.7,
  );
  final nov13 = BodyEntry(
    id: 'nov13',
    date: DateTime(year, 11, 13, 7),
    weightKg: 82.4,
  );
  final entries = [nov13, nov10, nov1, oct18];

  late _BodyListCubit list;
  late _ChartCubit chart;
  late _SummaryCubit summary;
  late _ProfileCubit profile;
  late _EntitlementCubit entitlement;

  setUp(() {
    list = _BodyListCubit();
    when(() => list.state).thenReturn(
      BodyListState(
        status: BodyListStatus.ready,
        entries: entries,
        bodyFat: const {'nov1': 19.5, 'oct18': 21.0},
      ),
    );
    chart = _ChartCubit();
    when(() => chart.state).thenReturn(
      BodyChartState(
        from: DateTime(year, 8, 20),
        to: DateTime(year, 11, 13),
        points: {
          BodySeries.weight: [
            SeriesPoint(oct18.date, 84.1),
            SeriesPoint(nov13.date, 82.4),
          ],
        },
      ),
    );
    summary = _SummaryCubit();
    when(() => summary.state).thenReturn(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: MeasurementSummary.of(
          after: nov1,
          before: oct18,
          profile: const UserProfile(targetWeightKg: 78),
          now: DateTime(year, 11, 13),
        ),
        candidates: [oct18],
        laterCandidates: [nov1],
      ),
    );
    profile = _ProfileCubit();
    when(() => profile.state).thenReturn(
      const ProfileState(
        status: ProfileStatus.loaded,
        profile: UserProfile(targetWeightKg: 78),
      ),
    );
    entitlement = _EntitlementCubit();
    when(() => entitlement.state).thenReturn(const EntitlementUnknown());
    sl
      ..registerSingleton<BodyListCubit>(list)
      ..registerFactoryParam<BodyChartCubit, int, void>((_, _) => chart)
      ..registerFactoryParam<MeasurementSummaryCubit, String?, void>(
        (_, _) => summary,
      );
  });

  tearDown(sl.reset);

  /// [page] at /body, every other route showing its location.
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view
      ..physicalSize = const Size(1200, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    Widget location(BuildContext _, GoRouterState state) =>
        Text('at ${state.uri.path}');
    final router = GoRouter(
      initialLocation: '/body',
      routes: [
        GoRoute(path: '/body', builder: (_, _) => page),
        GoRoute(
          path: '/:a',
          builder: location,
          routes: [
            GoRoute(
              path: ':b',
              builder: location,
              routes: [
                GoRoute(
                  path: ':c',
                  builder: location,
                  routes: [GoRoute(path: ':d', builder: location)],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<ProfileCubit>.value(value: profile),
          BlocProvider<EntitlementCubit>.value(value: entitlement),
        ],
        child: MaterialApp.router(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Overview: the boxes, the chart, the buttons, the history', (
    tester,
  ) async {
    await pump(tester, const BodyPage());

    expect(find.text('Body'), findsOneWidget);
    // Against Oct 18, the measurement day before the newest one.
    final weight = tester.widget<StatTile>(
      find.widgetWithText(StatTile, 'Weight'),
    );
    expect(weight.figure, '82.4 kg');
    expect(weight.change, '−1.7');
    expect(weight.changeIsGood, isTrue);
    final fat = tester.widget<StatTile>(
      find.widgetWithText(StatTile, 'Body fat'),
    );
    expect(
      (fat.figure, fat.change, fat.changeIsGood),
      ('19.5 %', '−1.5', true),
    );
    final lean = tester.widget<StatTile>(
      find.widgetWithText(StatTile, 'Lean mass'),
    );
    expect((lean.figure, lean.change), ('66.3 kg', '−0.1'));
    expect(lean.changeIsGood, isFalse);

    final card = tester.widget<MultiSeriesChart>(find.byType(MultiSeriesChart));
    expect(card.title, '12 weeks');
    expect(card.detail, 'target 78 kg');
    expect(card.series!.single.average, isNotNull);
    // Only a pair has its own tap tag.
    expect(card.series!.single.formatPoint, isNull);
    expect(card.series!.single.targetLabel, 'Target');
    // No older entries: no range control.
    expect(card.range, isNull);
    expect(card.lockedCaption, isNull);

    expect(find.text('Log weight'), findsOneWidget);
    expect(find.text('Measurement day'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    final rows = tester.widgetList<ListRow>(find.byType(ListRow)).toList();
    expect(rows.map((row) => row.title), [
      '82.4 kg',
      '82.7 kg',
      '82.9 kg',
      '84.1 kg',
    ]);
    expect(rows[2].detail, endsWith(' · measurement day'));
    expect(rows[2].value, '19.5 %');
    expect(rows[0].value, '—');
    expect(rows.every((row) => row.end == ListRowEnd.chevron), isTrue);

    await tester.tap(find.text('82.7 kg'));
    await tester.pumpAndSettle();
    expect(find.text('at /progress/body/nov10'), findsOneWidget);
  });

  testWidgets('a free user with older entries sees the locked ranges', (
    tester,
  ) async {
    when(() => list.state).thenReturn(
      BodyListState(
        status: BodyListStatus.ready,
        entries: entries,
        hasOlder: true,
        olderLocked: true,
      ),
    );
    await pump(tester, const BodyPage());

    final card = tester.widget<MultiSeriesChart>(find.byType(MultiSeriesChart));
    expect(card.range, isNotNull);
    expect(card.lockedCaption, 'See your older results with Premium');
  });

  testWidgets('no entries: the empty view and both buttons under it', (
    tester,
  ) async {
    when(() => list.state)
        .thenReturn(const BodyListState(status: BodyListStatus.ready));
    await pump(tester, const BodyPage());

    expect(find.text('No weigh-ins yet'), findsOneWidget);
    expect(find.text('Log weight'), findsOneWidget);
    expect(find.text('Measurement day'), findsOneWidget);
    expect(find.byType(ForgeSegmentedControl<bool>), findsOneWidget);

    // Compare shows the same.
    await tester.tap(find.text('Compare'));
    await tester.pump();
    expect(find.text('No weigh-ins yet'), findsOneWidget);
  });

  testWidgets('loading and failure keep the switch', (tester) async {
    when(() => list.state).thenReturn(const BodyListState());
    await pump(tester, const BodyPage());
    expect(find.byType(ForgeSegmentedControl<bool>), findsOneWidget);
    expect(find.byType(StatTile), findsNWidgets(3));

    when(() => list.state)
        .thenReturn(const BodyListState(status: BodyListStatus.failure));
    await pump(tester, const BodyPage());
    expect(find.byType(ForgeSegmentedControl<bool>), findsOneWidget);
    expect(find.text("Couldn't load your entries"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Compare: photos, the baseline, a box per side, the target', (
    tester,
  ) async {
    await pump(tester, const BodyPage(compareAfter: 'nov1'));

    verify(() => summary.showDay('nov1')).called(1);
    final slider = tester.widget<BeforeAfterSlider>(
      find.byType(BeforeAfterSlider),
    );
    final front = slider.views!.single;
    // Only Oct 18 has a front photo: it shows alone, on its date.
    expect(front.name, 'Front');
    expect(front.after, isNull);
    expect(front.beforeDate, 'Oct 18');
    // Not on this device and not being fetched: unavailable.
    expect(front.before.missing, 'Photo not on this device');
    expect(slider.onLaterDateTap, isNull);
    // One earlier day: no baseline choice.
    expect(find.text('Previous'), findsNothing);

    String? changeOf(String label) =>
        tester.widget<StatTile>(find.widgetWithText(StatTile, label)).change;
    expect(changeOf('Weight'), '−1.2');
    expect(changeOf('Waist'), '−3.5');
    expect(changeOf('Upper arm (L)'), '+0.5');
    expect(changeOf('Upper arm (R)'), '+0.3');
    expect(find.text('84.1 → 82.9 kg'), findsOneWidget);
    // No sex or height: no body fat, the profile's notice instead.
    expect(find.text('No body fat yet'), findsOneWidget);
    expect(find.text('Your profile'), findsOneWidget);

    final target = tester.widget<FeaturedCard>(find.byType(FeaturedCard));
    expect(target.title, 'Target 78 kg');
    expect(target.note, 'At this pace, around Dec 28.');
  });

  testWidgets('Compare without photos: the dates line opens the later days', (
    tester,
  ) async {
    final later = BodyEntry(
      id: 'later',
      date: DateTime(year, 11, 8),
      measurements: const {BodyMeasurement.waist: 88},
    );
    when(() => summary.state).thenReturn(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: MeasurementSummary.of(
          after: nov1,
          before: BodyEntry(
            id: 'oct18',
            date: oct18.date,
            weightKg: 84.1,
            measurements: oct18.measurements,
          ),
          profile: const UserProfile(),
          now: DateTime(year, 11, 13),
        ),
        candidates: [oct18, oct18],
        laterCandidates: [later, nov1],
      ),
    );
    await pump(tester, const BodyPage(compareAfter: 'nov1'));

    expect(find.text('No progress photos on these days'), findsOneWidget);
    expect(find.text('Oct 18 → Nov 1'), findsOneWidget);
    await tester.tap(find.text('Oct 18 → Nov 1'));
    await tester.pumpAndSettle();
    expect(find.text('Later day'), findsOneWidget);
    await tester.tap(find.text('Nov 8, $year'));
    await tester.pumpAndSettle();
    verify(() => summary.chooseAfter('later')).called(1);

    // Other date opens the earlier days, also when it is chosen already.
    await tester.tap(find.text('Other date'));
    await tester.pumpAndSettle();
    expect(find.text('Compare with'), findsOneWidget);
  });

  testWidgets('one measurement day shows its values alone', (tester) async {
    when(() => summary.state).thenReturn(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: MeasurementSummary.of(
          after: oct18,
          before: null,
          profile: const UserProfile(targetWeightKg: 78),
          now: DateTime(year, 11, 13),
        ),
      ),
    );
    await pump(tester, const BodyPage(compareAfter: 'oct18'));

    expect(
      find.text('No earlier measurement day to compare with yet.'),
      findsOneWidget,
    );
    expect(find.text('Values'), findsOneWidget);
    final arm = tester.widget<StatTile>(
      find.widgetWithText(StatTile, 'Upper arm (L / R)'),
    );
    expect(arm.figure, '36 / 35.5 cm');
    expect(
      tester
          .widget<BeforeAfterSlider>(find.byType(BeforeAfterSlider))
          .views!
          .single
          .after,
      isNull,
    );
    expect(
      tester.widget<FeaturedCard>(find.byType(FeaturedCard)).note,
      '6.1 kg to go.',
    );
  });

  testWidgets('no measurement day and a gone day', (tester) async {
    when(() => summary.state).thenReturn(
      const MeasurementSummaryState(
        status: MeasurementSummaryStatus.noMeasurementDays,
      ),
    );
    await pump(tester, const BodyPage(compareAfter: 'x'));
    expect(find.text('No measurement days yet'), findsOneWidget);
    await tester.tap(find.text('Measurement day'));
    await tester.pumpAndSettle();
    expect(find.text('at /progress/body/measure'), findsOneWidget);

    when(() => summary.state).thenReturn(
      const MeasurementSummaryState(status: MeasurementSummaryStatus.notFound),
    );
    await pump(tester, const BodyPage(compareAfter: 'x'));
    expect(find.text('This entry no longer exists.'), findsOneWidget);
    expect(find.text('Entry not found'), findsNothing);
  });

  testWidgets('Measurement summary: the dates head it, photos come last', (
    tester,
  ) async {
    when(() => summary.state).thenReturn(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: MeasurementSummary.of(
          after: nov1,
          before: oct18,
          profile: const UserProfile(sex: Sex.male, heightCm: 180),
          now: DateTime(year, 11, 13),
        ),
        candidates: [oct18],
      ),
    );
    await pump(tester, const MeasurementSummaryPage(id: 'nov1'));

    expect(find.text('Measurement summary'), findsOneWidget);
    expect(find.text('Oct 18 → Nov 1, $year'), findsOneWidget);
    expect(find.text('Measurement day saved'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    final photos = tester.getTopLeft(find.byType(BeforeAfterSlider)).dy;
    final weight = tester
        .getTopLeft(find.widgetWithText(StatTile, 'Weight'))
        .dy;
    expect(photos, greaterThan(weight));
    // No target weight: no target card.
    expect(find.byType(FeaturedCard), findsNothing);
  });

  testWidgets('a missing measurement names it', (tester) async {
    when(() => summary.state).thenReturn(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: MeasurementSummary.of(
          after: nov1,
          before: oct18,
          profile: const UserProfile(sex: Sex.male, heightCm: 180),
          now: DateTime(year, 11, 13),
        ),
      ),
    );
    await pump(tester, const BodyPage(compareAfter: 'nov1'));

    final notice = tester.widget<NoticeBanner>(find.byType(NoticeBanner));
    expect(notice.message, startsWith('Body fat needs'));
    expect(notice.action, isNull);
    expect(
      MeasurementSummary.of(
        after: nov1,
        before: oct18,
        profile: const UserProfile(sex: Sex.male, heightCm: 180),
        now: DateTime(year, 11, 13),
      ).bodyFat,
      isA<BodyFatNeedsMeasurements>(),
    );
  });

  testWidgets('both days\' photos: the later date opens the later days', (
    tester,
  ) async {
    final withPhoto = BodyEntry(
      id: 'nov1',
      date: nov1.date,
      weightKg: 82.9,
      photos: const {PhotoPose.front: 'front-2.jpg'},
    );
    when(() => summary.state).thenReturn(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: MeasurementSummary.of(
          after: withPhoto,
          before: oct18,
          profile: const UserProfile(),
          now: DateTime(year, 11, 13),
        ),
        laterCandidates: [nov13, withPhoto],
        fetching: const {'front-2.jpg'},
      ),
    );
    await pump(tester, const BodyPage(compareAfter: 'nov1'));

    final slider = tester.widget<BeforeAfterSlider>(
      find.byType(BeforeAfterSlider),
    );
    final front = slider.views!.single;
    expect(front.change, '−1.2 kg');
    expect(front.after!.image, isNull);
    expect(front.after!.missing, isNull);
    slider.onLaterDateTap!();
    // The fetched photo shimmers on: no settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Later day'), findsOneWidget);
  });

  testWidgets('without a target weight the weight change is neutral', (
    tester,
  ) async {
    when(() => profile.state)
        .thenReturn(const ProfileState(status: ProfileStatus.loaded));
    await pump(tester, const BodyPage());

    final weight = tester.widget<StatTile>(
      find.widgetWithText(StatTile, 'Weight'),
    );
    expect(weight.change, '−1.7');
    expect(weight.changeIsGood, isNull);
  });

  testWidgets('a pair\'s chart values name both sides', (tester) async {
    when(() => chart.state).thenReturn(
      BodyChartState(
        shown: const [BodySeries.upperArm],
        from: DateTime(year, 8, 20),
        to: DateTime(year, 11, 13),
        points: {
          BodySeries.upperArm: [
            SeriesPoint(oct18.date, 35.75, const [36, 35.5]),
            // The same mean on another day keeps its own sides.
            SeriesPoint(nov1.date, 35.75, const [35, 36.5]),
          ],
        },
      ),
    );
    await pump(tester, const BodyPage());

    final card = tester.widget<MultiSeriesChart>(find.byType(MultiSeriesChart));
    final tag = card.series!.single.formatPoint!;
    expect(tag((day: oct18.date, value: 35.75)), '36 / 35.5 cm');
    expect(tag((day: nov1.date, value: 35.75)), '35 / 36.5 cm');
  });

  testWidgets('empty and error states sit in cards', (tester) async {
    when(() => list.state)
        .thenReturn(const BodyListState(status: BodyListStatus.failure));
    await pump(tester, const BodyPage());
    expect(
      find.descendant(
        of: find.byType(ListRowCard),
        matching: find.byType(ErrorView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty range keeps the range control and locked caption', (
    tester,
  ) async {
    when(() => list.state).thenReturn(
      BodyListState(
        status: BodyListStatus.ready,
        entries: entries,
        hasOlder: true,
        olderLocked: true,
      ),
    );
    when(() => chart.state).thenReturn(const BodyChartState());
    await pump(tester, const BodyPage());

    final card = tester.widget<MultiSeriesChart>(find.byType(MultiSeriesChart));
    expect(card.series, isNull);
    expect(card.range, isNotNull);
    expect(card.lockedCaption, 'See your older results with Premium');
    expect(find.text('Nothing in this range'), findsOneWidget);
    expect(find.text('Nothing to show in this range yet.'), findsOneWidget);
  });

  testWidgets('no weight change: the photo line has only the dates', (
    tester,
  ) async {
    BodyEntry photographed(String id, DateTime date) =>
        BodyEntry(id: id, date: date, photos: {PhotoPose.front: '$id.jpg'});
    when(() => summary.state).thenReturn(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: MeasurementSummary.of(
          after: photographed('b', nov1.date),
          before: photographed('a', oct18.date),
          profile: const UserProfile(),
          now: DateTime(year, 11, 13),
        ),
      ),
    );
    await pump(tester, const BodyPage(compareAfter: 'b'));

    final slider = tester.widget<BeforeAfterSlider>(
      find.byType(BeforeAfterSlider),
    );
    expect(slider.views!.single.change, isNull);
  });

  group('Log weight', () {
    late _WeightFormCubit form;
    late StreamController<WeightFormState> states;
    WeightFormSetup? opened;

    setUp(() {
      form = _WeightFormCubit();
      states = StreamController<WeightFormState>();
      final start = WeightFormState(date: DateTime.now(), weight: 82.4);
      whenListen(form, states.stream, initialState: start);
      when(() => form.isEditing).thenReturn(false);
      when(form.save).thenAnswer((_) async {});
      sl.registerFactoryParam<WeightFormCubit, WeightFormSetup, WeightUnit>((
        setup,
        _,
      ) {
        opened = setup;
        return form;
      });
    });

    tearDown(() => states.close());

    testWidgets('opens a sheet over Body, its ruler at the last weigh-in', (
      tester,
    ) async {
      await pump(tester, const BodyPage());

      await tester.tap(find.widgetWithText(ForgeButton, 'Log weight'));
      await tester.pumpAndSettle();

      expect(opened, (initial: null, startKg: 82.4));
      final sheet = find.byType(ForgeBottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Log weight')),
        findsOneWidget,
      );
      final ruler = tester.widget<NumberPicker>(find.byType(NumberPicker));
      expect((ruler.value, ruler.unit), (82.4, 'kg'));
      expect(find.textContaining('Today, '), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);

      await tester.tap(find.text('Save'));
      verify(form.save).called(1);
    });

    testWidgets('a failed save says so over the sheet, which stays', (
      tester,
    ) async {
      await pump(tester, const BodyPage());
      await tester.tap(find.widgetWithText(ForgeButton, 'Log weight'));
      await tester.pumpAndSettle();

      states.add(
        WeightFormState(
          date: DateTime.now(),
          weight: 82.4,
          status: WeightFormStatus.saveFailed,
          failure: const UnknownFailure(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(ForgeSnackbar), findsOneWidget);
      expect(find.text("Couldn't save. Try again"), findsOneWidget);
      expect(find.byType(ForgeBottomSheet), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(ForgeSnackbar), findsNothing);
    });

    testWidgets('closes once saved', (tester) async {
      await pump(tester, const BodyPage());
      await tester.tap(find.widgetWithText(ForgeButton, 'Log weight'));
      await tester.pumpAndSettle();

      states.add(
        WeightFormState(
          date: DateTime.now(),
          weight: 82.4,
          status: WeightFormStatus.saved,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ForgeBottomSheet), findsNothing);
    });
  });
}
