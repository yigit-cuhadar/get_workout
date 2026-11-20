import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The event names Analytics refuses (firebase_analytics'
/// `_reservedEventNames`): logging one throws, and the telemetry only logs
/// that at debug level, so the event is lost without a trace.
const _reservedEvents = {
  'ad_activeview',
  'ad_click',
  'ad_exposure',
  'ad_query',
  'ad_reward',
  'adunit_exposure',
  'app_background',
  'app_clear_data',
  'app_exception',
  'app_remove',
  'app_store_refund',
  'app_store_subscription_cancel',
  'app_store_subscription_convert',
  'app_store_subscription_renew',
  'app_uninstall',
  'app_update',
  'app_upgrade',
  'dynamic_link_app_open',
  'dynamic_link_app_update',
  'dynamic_link_first_open',
  'error',
  'first_open',
  'first_visit',
  'in_app_purchase',
  'notification_dismiss',
  'notification_foreground',
  'notification_open',
  'notification_receive',
  'os_update',
  'session_start',
  'session_start_with_rollout',
  'user_engagement',
};

/// User property names Analytics sets itself.
const _reservedProperties = {
  'first_open_time',
  'first_visit_time',
  'last_deep_link_referrer',
  'user_id',
  'first_open_after_install',
};

void main() {
  final source = File('lib/features/analytics/domain/analytics.dart')
      .readAsStringSync();
  final events = {
    for (final m in RegExp(r"_log\(\s*'([^']+)'").allMatches(source))
      m.group(1)!,
  };
  final properties = {
    for (final m in RegExp(r"_property\(\s*'([^']+)'").allMatches(source))
      m.group(1)!,
  };

  test('the catalog is found', () {
    expect(events, isNotEmpty);
    expect(properties, isNotEmpty);
  });

  test('no event name is one Analytics refuses', () {
    for (final name in events) {
      expect(_reservedEvents, isNot(contains(name)), reason: name);
      expect(name, matches(RegExp(r'^[a-z][a-z0-9_]{0,39}$')), reason: name);
      expect(
        name,
        isNot(matches(RegExp(r'^(firebase_|google_|ga_)'))),
        reason: name,
      );
    }
  });

  test('no user property name is one Analytics sets or refuses', () {
    for (final name in properties) {
      expect(_reservedProperties, isNot(contains(name)), reason: name);
      expect(name, matches(RegExp(r'^[a-z][a-z0-9_]{0,23}$')), reason: name);
      expect(
        name,
        isNot(matches(RegExp(r'^(firebase_|google_|ga_)'))),
        reason: name,
      );
    }
  });
}
