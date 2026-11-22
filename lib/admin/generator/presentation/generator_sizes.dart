/// The widths the Generator page gives its fields and panes (AG1, AG2,
/// AG5 boards), in one place.
abstract final class GeneratorSizes {
  /// A number in a table cell, and each end of a `[min, max]` range.
  static const number = 64.0;
  static const rangeEnd = 48.0;

  /// A short field: a priority, a score, a slot's key.
  static const short = 100.0;

  /// A labelled number.
  static const labelled = 120.0;

  /// A number with a longer label, a days dropdown.
  static const medium = 160.0;

  /// An id, a dropdown, a number with a long label.
  static const wide = 220.0;

  /// The split dropdown.
  static const split = 240.0;

  /// The simulator's answers.
  static const answers = 250.0;

  /// The template list, and the most a slot's pick chips take.
  static const list = 260.0;

  /// A day's name.
  static const name = 320.0;

  /// The review dialog.
  static const dialog = 640.0;

  /// The most the review's change table takes before it scrolls.
  static const changesHeight = 240.0;
}
