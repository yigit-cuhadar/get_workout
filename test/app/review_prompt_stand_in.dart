import 'package:forge_core/forge_core.dart';
import 'package:forge_review/forge_review.dart';
import 'package:get_workout/features/feedback/feedback_module.dart';
import 'package:mocktail/mocktail.dart';

class MockReviews extends Mock implements ReviewRepository {}

/// A history that asked in this version already, so no moment asks.
const askedThisVersion = ReviewHistory(askedVersion: '1.0.0');

/// Registers the summary's [ReviewPromptCubit] over [history], in app
/// version 1.0.0, and returns its repository.
MockReviews registerReviewPrompt({ReviewHistory history = askedThisVersion}) {
  registerFallbackValue(const ReviewHistory());
  final reviews = MockReviews();
  when(reviews.load).thenAnswer((_) async => Ok(history));
  when(() => reviews.save(any())).thenAnswer((_) async => const Ok(null));
  when(reviews.appVersion).thenAnswer((_) async => const Ok('1.0.0'));
  when(reviews.requestReview).thenAnswer((_) async => const Ok(null));
  sl.registerFactory(
    () => ReviewPromptCubit(
      reachMoment: ReachReviewMoment(reviews, FeedbackModule.reviewRules),
      requestStoreReview: RequestStoreReview(reviews),
    ),
  );
  return reviews;
}
