import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/programs/domain/catalogue_program.dart';
import '../../../features/programs/domain/catalogue_rules.dart';
import '../../../features/programs/domain/program.dart';
import '../../../features/programs/domain/program_editing.dart';

/// A ready-made program as the editor holds it: the fields of
/// `programs/{id}` and `programs/{id}/detail/main` that are typed in, any of
/// them possibly unset or invalid until the catalogue rules pass. The
/// fields computed from the days (`daysPerWeek`, `equipment`, `minutes`) are
/// not held but derived by [content].
///
/// A required number of an item that is unset is -1, as in [ProgramEntry],
/// so the rules report it.
class ProgramDraft extends Equatable {
  const ProgramDraft({
    this.id = '',
    this.status = ExerciseStatus.draft,
    this.premium = false,
    this.level,
    this.goal,
    this.equipmentProfile,
    this.order,
    this.lengthWeeks,
    this.text = const {},
    this.days = const [],
  });

  /// Reads the content-file shape leniently, like [ExerciseDraft.fromJson]:
  /// an unknown code or a value of the wrong type becomes unset.
  factory ProgramDraft.fromJson(Map<String, Object?> json) {
    final entry = ProgramEntry(json);
    final l10n = json['l10n'];
    return ProgramDraft(
      id: json['id'] is String ? json['id']! as String : '',
      status:
          ExerciseStatus.values.byCode(json['status']) ?? ExerciseStatus.draft,
      premium: json['premium'] == true,
      level: entry.level,
      goal: Goal.values.byCode(json['goal']),
      equipmentProfile: EquipmentProfile.values.byCode(
        json['equipmentProfile'],
      ),
      order: json['order'] is int ? json['order']! as int : null,
      lengthWeeks: json['lengthWeeks'] is int
          ? json['lengthWeeks']! as int
          : null,
      text: {
        for (final language in languages)
          if ((l10n is Map ? l10n[language] : null)
              case final Map<Object?, Object?> text)
            language: CatalogueText(
              name: text['name'] is String ? text['name']! as String : '',
              summary: text['summary'] is String
                  ? text['summary']! as String
                  : '',
            ),
      },
      days: entry.program.days,
    );
  }

  final String id;
  final ExerciseStatus status;
  final bool premium;
  final Level? level;
  final Goal? goal;
  final EquipmentProfile? equipmentProfile;
  final int? order;

  /// Null for a program that runs until it is stopped.
  final int? lengthWeeks;

  /// By language, for the languages of `content_rules.dart`.
  final Map<String, CatalogueText> text;
  final List<ProgramDay> days;

  CatalogueText textOf(String language) =>
      text[language] ?? const CatalogueText(name: '', summary: '');

  /// The content-file shape the catalogue rules check and the repository
  /// stores, with `daysPerWeek`, `equipment` and `minutes` computed from
  /// the days and [exercises] (every exercise by id). Unset required fields
  /// are written as null so the rules report them; a language without text
  /// is left out, but English, which is required.
  Map<String, Object?> content(Map<String, ExerciseEntry> exercises) {
    final json = <String, Object?>{
      'id': id,
      'status': status.code,
      'premium': premium,
      'order': order,
      'level': level?.code,
      'goal': goal?.code,
      'equipmentProfile': equipmentProfile?.code,
      'daysPerWeek': days.length,
      'lengthWeeks': ?lengthWeeks,
      'l10n': {
        for (final language in languages)
          if (language == CatalogueProgram.fallbackLanguage ||
              textOf(language) != const CatalogueText(name: '', summary: ''))
            language: {
              'name': textOf(language).name,
              'summary': textOf(language).summary,
            },
      },
      'days': [for (final day in days) _dayJson(day)],
    };
    json['equipment'] = programEquipment(ProgramEntry(json), exercises);
    if (sessionMinutes(days) case (:final min, :final max)) {
      json['minutes'] = {'min': min, 'max': max};
    }
    return json;
  }

  static Map<String, Object?> _dayJson(ProgramDay day) => {
    'name': day.name,
    'items': [
      for (final item in day.items)
        {
          'exerciseId': item.exerciseId,
          'sets': item.sets,
          'repMin': ?item.repMin,
          'repMax': ?item.repMax,
          'durationS': ?item.durationS,
          'restS': item.restS,
          'group': ?item.group,
        },
    ],
  };

  static const _unset = Object();

  /// Pass null to clear an optional field.
  ProgramDraft copyWith({
    String? id,
    ExerciseStatus? status,
    bool? premium,
    Object? level = _unset,
    Object? goal = _unset,
    Object? equipmentProfile = _unset,
    Object? order = _unset,
    Object? lengthWeeks = _unset,
    Map<String, CatalogueText>? text,
    List<ProgramDay>? days,
  }) {
    T? pick<T>(Object? value, T? current) =>
        identical(value, _unset) ? current : value as T?;
    return ProgramDraft(
      id: id ?? this.id,
      status: status ?? this.status,
      premium: premium ?? this.premium,
      level: pick(level, this.level),
      goal: pick(goal, this.goal),
      equipmentProfile: pick(equipmentProfile, this.equipmentProfile),
      order: pick(order, this.order),
      lengthWeeks: pick(lengthWeeks, this.lengthWeeks),
      text: text ?? this.text,
      days: days ?? this.days,
    );
  }

  /// [text] with [language]'s replaced.
  ProgramDraft withText(String language, CatalogueText value) =>
      copyWith(text: {...text, language: value});

  @override
  List<Object?> get props => [
    id,
    status,
    premium,
    level,
    goal,
    equipmentProfile,
    order,
    lengthWeeks,
    text,
    days,
  ];
}

/// When the card and the detail of a stored program last changed; null
/// while the server has not confirmed a write, or for a missing document.
typedef ProgramVersion = ({DateTime? card, DateTime? detail});

/// A stored program as the panel reads it.
class ProgramRecord extends Equatable {
  ProgramRecord({required this.json, required this.version})
    : draft = ProgramDraft.fromJson(json);

  /// The card in the content-file shape, with `id`, and with `days` when the
  /// detail was read; without `updatedAt` and `contentHash`, but with any
  /// unknown field of the card.
  final Map<String, Object?> json;
  final ProgramVersion version;
  final ProgramDraft draft;

  String get id => draft.id;

  /// As stored on the card.
  int? get daysPerWeek => switch (json['daysPerWeek']) {
    final int days => days,
    _ => null,
  };

  @override
  List<Object?> get props => [json, version];
}

/// How a save ended when Firestore was reached.
sealed class ProgramSaveOutcome extends Equatable {
  const ProgramSaveOutcome();

  @override
  List<Object?> get props => [];
}

final class ProgramSaved extends ProgramSaveOutcome {
  const ProgramSaved(this.record);

  /// The program as stored, with its new version; null when the write went
  /// through but reading it back failed.
  final ProgramRecord? record;

  @override
  List<Object?> get props => [record];
}

/// A new program's id is already used; nothing was written.
final class ProgramIdTaken extends ProgramSaveOutcome {
  const ProgramIdTaken();
}

/// The card or the detail changed since the editor loaded them; nothing was
/// written.
final class ProgramChangedSinceLoaded extends ProgramSaveOutcome {
  const ProgramChangedSinceLoaded();
}
