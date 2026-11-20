import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_form_cubit.dart';
import 'package:get_workout/features/profile/presentation/profile_questions.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../component_harness.dart';
import '../../fake_analytics.dart';

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _CompleteOnboarding extends Mock implements CompleteOnboarding {}

void main() {
  late _SettingsCubit settings;

  setUp(() {
    settings = _SettingsCubit();
    when(() => settings.state).thenReturn(
      const SettingsState(
        UserSettings(weightUnit: WeightUnit.kg, lengthUnit: LengthUnit.cm),
        loaded: true,
      ),
    );
  });

  Future<void> pump(
    WidgetTester tester,
    ProfileFormCubit form, {
    bool onboarding = false,
  }) => pumpComponent(
    tester,
    MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: settings),
        BlocProvider<ProfileFormCubit>.value(value: form),
      ],
      child: ProfileQuestion(ProfileField.daysPerWeek, onboarding: onboarding),
    ),
  );

  ProfileFormCubit editing(Level? level) => ProfileFormCubit.edit(
    field: ProfileField.daysPerWeek,
    initial: UserProfile(level: level),
  );

  /// The label of the row carrying the tag.
  String? taggedRow(WidgetTester tester) {
    final options = tester.widget<ChoiceGrid>(find.byType(ChoiceGrid)).options;
    final tagged = options.where((option) => option.tag != null).toList();
    if (tagged.isEmpty) return null;
    expect(tagged, hasLength(1));
    expect(tagged.single.tag!.label, 'Recommended');
    expect(tagged.single.tag!.kind, ForgeTagKind.record);
    return tagged.single.label;
  }

  int? selected(WidgetTester tester) =>
      tester.widget<ChoiceGrid>(find.byType(ChoiceGrid)).selected;

  for (final (level, days, info) in [
    (Level.beginner, 3, 'Most beginners train 3 days a week.'),
    (Level.intermediate, 4, 'Most intermediate lifters train 4 days a week.'),
    (Level.advanced, 5, 'Most advanced lifters train 5 days a week.'),
  ]) {
    testWidgets('editing with a saved ${level.name} level recommends $days '
        'days, selecting nothing', (tester) async {
      final form = editing(level);
      addTearDown(form.close);
      await pump(tester, form);

      expect(find.text(info), findsOneWidget);
      expect(taggedRow(tester), '$days days');
      expect(find.text('Recommended'), findsOneWidget);
      expect(selected(tester), isNull);
      expect(form.state.answers.daysPerWeek, isNull);
    });
  }

  testWidgets('with no level known, neither the line nor the tag shows', (
    tester,
  ) async {
    final form = editing(null);
    addTearDown(form.close);
    await pump(tester, form);

    expect(find.textContaining('Most '), findsNothing);
    expect(taggedRow(tester), isNull);
    expect(find.text('Recommended'), findsNothing);
  });

  testWidgets('a saved answer stays the one selected beside the tag', (
    tester,
  ) async {
    final form = ProfileFormCubit.edit(
      field: ProfileField.daysPerWeek,
      initial: const UserProfile(level: Level.beginner, daysPerWeek: 5),
    );
    addTearDown(form.close);
    await pump(tester, form);

    expect(taggedRow(tester), '3 days');
    expect(selected(tester), 3);
  });

  testWidgets('in onboarding the level just answered sets the recommendation; '
      'a tap on the tagged row picks it', (tester) async {
    final form = ProfileFormCubit.onboarding(
      analytics: fakeAnalytics(),
      uid: 'uid',
      initial: const UserProfile(),
      completeOnboarding: _CompleteOnboarding(),
    )..setLevel(Level.intermediate);
    addTearDown(form.close);
    await pump(tester, form, onboarding: true);

    expect(
      find.text('Most intermediate lifters train 4 days a week.'),
      findsOneWidget,
    );
    expect(taggedRow(tester), '4 days');
    expect(selected(tester), isNull);

    form.setLevel(Level.advanced);
    await tester.pump();
    expect(find.text('Most advanced lifters train 5 days a week.'), findsOne);
    expect(taggedRow(tester), '5 days');

    await tester.tap(find.text('Recommended'));
    await tester.pump();
    expect(form.state.answers.daysPerWeek, 5);
    expect(selected(tester), 3);
  });
}
