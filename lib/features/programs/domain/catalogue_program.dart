import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import 'program.dart';
import 'program_editing.dart';

class CatalogueText extends Equatable {
  const CatalogueText({required this.name, required this.summary});

  final String name;
  final String summary;

  @override
  List<Object?> get props => [name, summary];
}

/// A ready-made program's card (`programs/{id}`): what the catalogue lists
/// for everyone. Its days are read separately, and only where the rules
/// allow (see `CatalogueRepository.getDays`).
class CatalogueProgram extends Equatable {
  const CatalogueProgram({
    required this.id,
    required this.premium,
    required this.level,
    required this.goal,
    required this.daysPerWeek,
    this.lengthWeeks,
    this.equipment,
    this.minutes,
    required this.equipmentProfile,
    required this.order,
    required this.l10n,
  });

  static const fallbackLanguage = 'en';

  final String id;
  final bool premium;
  final Level level;
  final Goal goal;
  final int daysPerWeek;
  final int? lengthWeeks;

  /// The primary equipment of every exercise, in vocabulary order; null
  /// when the card's list is missing, empty or has a code this app does not
  /// know, so it cannot tell what is needed.
  final List<Equipment>? equipment;

  /// The shortest and longest session; null when the card has none.
  final SessionMinutes? minutes;

  /// Every exercise can be done with this profile's equipment, through its
  /// own equipment or an alternative set.
  final EquipmentProfile equipmentProfile;

  /// The catalogue's default sort.
  final int order;

  /// By language; always has [fallbackLanguage].
  final Map<String, CatalogueText> l10n;

  CatalogueText text(String language) =>
      l10n[language] ?? l10n[fallbackLanguage]!;

  /// Whether someone owning [owned] (bodyweight is always available) can do
  /// every exercise: they own all of [equipment], or all of the
  /// [equipmentProfile], which every exercise fits.
  bool fits(Set<Equipment> owned) {
    final equipment = this.equipment;
    return (equipment != null &&
            equipment.every(
              (e) => e == Equipment.bodyweight || owned.contains(e),
            )) ||
        owned.containsAll(equipmentProfile.equipment);
  }

  /// The user's own copy of this program with [days], named in [language].
  Program copy(List<ProgramDay> days, String language) => Program(
    name: text(language).name,
    origin: ProgramOrigin.catalog,
    sourceId: id,
    lengthWeeks: lengthWeeks,
    days: days,
    premium: premium,
  );

  @override
  List<Object?> get props => [
    id,
    premium,
    level,
    goal,
    daysPerWeek,
    lengthWeeks,
    equipment,
    minutes,
    equipmentProfile,
    order,
    l10n,
  ];
}
