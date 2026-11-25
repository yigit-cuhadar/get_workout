import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_messaging/forge_messaging.dart';
import 'package:get_workout/features/notifications/domain/notification_repository.dart';
import 'package:get_workout/features/notifications/domain/notifications_usecases.dart';
import 'package:mocktail/mocktail.dart';

class MockTopicRepository extends Mock implements TopicRepository {}

void main() {
  late MockTopicRepository topics;
  late FollowAnnouncements follow;

  setUp(() {
    topics = MockTopicRepository();
    follow = FollowAnnouncements(topics);
    when(() => topics.follow(any(), segment: any(named: 'segment')))
        .thenAnswer((_) async => const Ok(null));
  });

  test('while Premium is unknown it follows the language only', () async {
    await follow((language: 'en', premium: null));

    verify(() => topics.follow('en')).called(1);
  });

  test('follows the free or the Premium users by the Premium state', () async {
    await follow((language: 'en', premium: false));
    await follow((language: 'en', premium: true));

    verifyInOrder([
      () => topics.follow('en', segment: 'free'),
      () => topics.follow('en', segment: 'premium'),
    ]);
  });

  test('names the topics sendAnnouncement sends to', () {
    const topics = LanguageTopics(
      AnnouncementTopics.prefix,
      languages: ['en'],
      segments: [AnnouncementTopics.free, AnnouncementTopics.premium],
    );

    expect(topics.topic('en'), 'announcements_en');
    expect(
      topics.topic('en', segment: AnnouncementTopics.free),
      'announcements_en_free',
    );
    expect(
      topics.topic('en', segment: AnnouncementTopics.premium),
      'announcements_en_premium',
    );
  });
}
