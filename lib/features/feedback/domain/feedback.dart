import 'package:forge_core/forge_core.dart';

/// Where the user opened the feedback form, stored as its name.
enum FeedbackSource {
  /// Profile › Help & feedback.
  profile,

  /// "Write to us" after answering "Not really" to the review prompt.
  rating,
}

/// What `users/{uid}/feedback` accepts; firestore.rules checks the same.
abstract final class FeedbackLimits {
  static const message = 2000;
  static const email = 254;
}

/// Why a message cannot be sent yet.
enum FeedbackProblem { emptyMessage, longMessage, badEmail }

/// The message as the user types it, and where the form was opened.
class FeedbackDraft extends Equatable {
  const FeedbackDraft({
    required this.source,
    this.message = '',
    this.email = '',
  });

  final FeedbackSource source;
  final String message;

  /// Where to reply; empty when the user leaves none.
  final String email;

  /// The text as it is sent.
  FeedbackDraft get trimmed => FeedbackDraft(
    source: source,
    message: message.trim(),
    email: email.trim(),
  );

  /// What stops sending, by the trimmed text. An email needs one "@" with
  /// text on both sides and a dot after it; the reply proves the rest.
  Set<FeedbackProblem> get problems {
    final text = trimmed;
    return {
      if (text.message.isEmpty) FeedbackProblem.emptyMessage,
      if (text.message.length > FeedbackLimits.message)
        FeedbackProblem.longMessage,
      if (text.email.isNotEmpty &&
          (text.email.length > FeedbackLimits.email ||
              !_email.hasMatch(text.email)))
        FeedbackProblem.badEmail,
    };
  }

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  FeedbackDraft copyWith({String? message, String? email}) => FeedbackDraft(
    source: source,
    message: message ?? this.message,
    email: email ?? this.email,
  );

  @override
  List<Object?> get props => [source, message, email];
}
