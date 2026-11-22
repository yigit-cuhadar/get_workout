import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../../app/functions_region.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../domain/generated_program.dart';
import '../domain/generator_options.dart';
import '../domain/generator_repository.dart';

/// Generates through the callable `generateProgram` and reads what the
/// questions offer from `generator/options` (SPEC.md, Cloud Functions and
/// Data model).
class ServerGeneratorRepository implements GeneratorRepository {
  const ServerGeneratorRepository(this._functions, this._firestore);

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  static const region = functionsRegion;
  static const function = 'generateProgram';

  /// `details.reason` of the function's refusals
  /// (`functions/src/generator/store.ts`, `Reason`).
  static const _reasons = {
    'not-premium': GenerationRefusal.notPremium,
    'no-rules': GenerationRefusal.noRules,
    'no-template': GenerationRefusal.noTemplate,
    'no-exercises': GenerationRefusal.noExercises,
    'invalid-input': GenerationRefusal.invalidInput,
  };

  @override
  Future<Result<GeneratedProgram>> generate(GenerationRequest request) =>
      guard(() async {
        final result = await _functions
            .httpsCallable(function)
            .call<Object?>(requestData(request));
        return programFrom(result.data);
      }, mapper: _mapError);

  @override
  Stream<GeneratorOptions> watchOptions() => _firestore
      .doc('generator/options')
      .snapshots()
      .transform(
        StreamTransformer.fromHandlers(
          handleData: (snap, sink) {
            final data = snap.data();
            if (data == null) {
              // Offline, a document never loaded reads as missing.
              sink.addError(
                snap.metadata.isFromCache
                    ? const NetworkFailure('generator options not cached')
                    : const NotFoundFailure('no generator options'),
              );
              return;
            }
            final options = optionsFrom(data);
            if (options == null) {
              Log.e('generator', 'unreadable generator options');
              sink.addError(const UnknownFailure('unreadable options'));
              return;
            }
            sink.add(options);
          },
          handleError: (error, stack, sink) {
            final failure =
                mapFirebaseError(error) ?? UnknownFailure('$error', error);
            Log.e('generator', failure.message, error, stack);
            sink.addError(failure, stack);
          },
        ),
      );

  /// The callable's input for [request]; optional fields only when set.
  static Map<String, Object?> requestData(GenerationRequest request) {
    final answers = request.answers;
    List<String> codes<T extends Coded>(List<T> all, Set<T> picked) => [
      for (final value in all)
        if (picked.contains(value)) value.code,
    ];
    return {
      'answers': {
        'goal': answers.goal.code,
        'level': answers.level.code,
        'daysPerWeek': answers.daysPerWeek,
        'sessionMinutes': answers.sessionMinutes,
        'equipment': codes(Equipment.values, answers.equipment),
        'focus': codes(FocusArea.values, answers.focus),
        'skip': codes(FocusArea.values, answers.skip),
        'sensitive': codes(SensitiveArea.values, answers.sensitive),
        'equipmentStyle': answers.equipmentStyle.code,
        'split': ?answers.splitId,
      },
      'seed': request.seed,
      if (request.kept.any((day) => day.isNotEmpty))
        'kept': [
          for (final day in request.kept) [for (final item in day) _kept(item)],
        ],
      'lang': request.language,
    };
  }

  /// A kept item with only the fields the server takes.
  static Map<String, Object?> _kept(ProgramItem item) => {
    'exerciseId': item.exerciseId,
    'sets': item.sets,
    'restS': item.restS,
    if (item.durationS case final duration?)
      'durationS': duration
    else ...{
      'repMin': item.repMin,
      'repMax': item.repMax,
    },
  };

  /// The callable's result; a [FormatException] when it is not one.
  static GeneratedProgram programFrom(Object? data) {
    final program = _map(data)['program'];
    final days = _map(program)['days'];
    final uncovered = _map(data)['uncovered'];
    if (days is! List || days.isEmpty || uncovered is! List) {
      throw const FormatException('generateProgram: no days');
    }
    return GeneratedProgram(
      splitName: _string(_map(program)['name']),
      lengthWeeks: _int(_map(program)['lengthWeeks']),
      days: [
        for (final day in days)
          ProgramDay(
            name: _string(_map(day)['name']),
            items: switch (_map(day)['items']) {
              final List<Object?> items => [for (final i in items) _item(i)],
              _ => throw const FormatException('generateProgram: items'),
            },
          ),
      ],
      uncovered: {
        for (final code in uncovered)
          Muscle.values.byCode(code) ??
              (throw FormatException('generateProgram: muscle $code')),
      },
    );
  }

  static ProgramItem _item(Object? data) {
    final item = _map(data);
    final group = item['group'];
    return ProgramItem(
      exerciseId: _string(item['exerciseId']),
      sets: _int(item['sets']),
      repMin: _optionalInt(item['repMin']),
      repMax: _optionalInt(item['repMax']),
      durationS: _optionalInt(item['durationS']),
      restS: _int(item['restS']),
      group: group == null ? null : _string(group),
    );
  }

  static Map<Object?, Object?> _map(Object? value) => switch (value) {
    final Map<Object?, Object?> map => map,
    _ => throw const FormatException('generateProgram: not an object'),
  };

  static String _string(Object? value) => switch (value) {
    final String text when text.isNotEmpty => text,
    _ => throw const FormatException('generateProgram: not a text'),
  };

  static int _int(Object? value) =>
      _whole(value) ??
      (throw const FormatException('generateProgram: not a whole number'));

  static int? _optionalInt(Object? value) => value == null ? null : _int(value);

  /// Platform channels may hand a whole number over as a double.
  static int? _whole(Object? value) =>
      value is num && value.isFinite && value == value.roundToDouble()
      ? value.toInt()
      : null;

  /// `generator/options`, unknown fields ignored; a split it cannot read is
  /// left out. Null when what every question needs is missing.
  static GeneratorOptions? optionsFrom(Map<String, Object?> data) {
    final minutes = data['sessionMinutes'];
    final maxFocus = _whole(data['maxFocusAreas']);
    final maxSkip = _whole(data['maxSkipAreas']);
    final sessionMinutes = [
      if (minutes is List)
        for (final value in minutes) ?_whole(value),
    ];
    if (sessionMinutes.isEmpty || maxFocus == null || maxSkip == null) {
      return null;
    }
    return GeneratorOptions(
      splits: [
        if (data['splits'] case final List<Object?> splits)
          for (final split in splits) ?_split(split),
      ],
      sessionMinutes: sessionMinutes,
      maxFocusAreas: maxFocus,
      maxSkipAreas: maxSkip,
    );
  }

  static GeneratorSplit? _split(Object? data) {
    if (data is! Map) return null;
    final id = data['id'];
    final l10n = <String, SplitText>{
      if (data['l10n'] case final Map<Object?, Object?> l10n)
        for (final MapEntry(:key, :value) in l10n.entries)
          if (key is String && value is Map)
            if ((value['name'], value['info']) case (
              final String name,
              final String info,
            ))
              key: (name: name, info: info),
    };
    if (id is! String || !l10n.containsKey(GeneratorSplit.fallbackLanguage)) {
      return null;
    }
    return GeneratorSplit(
      id: id,
      l10n: l10n,
      fits: [
        if (data['fits'] case final List<Object?> fits)
          for (final fit in fits) ?_fit(fit),
      ],
    );
  }

  static SplitFit? _fit(Object? data) {
    if (data is! Map) return null;
    final days = _whole(data['days']);
    final levels = data['levels'];
    final goals = data['goals'];
    if (days == null || levels is! List) return null;
    return SplitFit(
      days: days,
      levels: {for (final code in levels) ?Level.values.byCode(code)},
      goals: goals is List
          ? {for (final code in goals) ?Goal.values.byCode(code)}
          : null,
    );
  }

  static Failure? _mapError(Object error) {
    if (error is FormatException) {
      return UnknownFailure('malformed generateProgram result', error);
    }
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final details = error.details;
    final reason = details is Map ? _reasons[details['reason']] : null;
    if (reason == null) return mapFirebaseError(error);
    return GenerationRefused(reason, error.message ?? error.code, cause: error);
  }
}
