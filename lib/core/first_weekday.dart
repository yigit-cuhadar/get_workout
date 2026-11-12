import 'package:flutter/material.dart';

extension FirstWeekday on MaterialLocalizations {
  /// The locale's first day of the week as an ISO weekday (1 Monday to
  /// 7 Sunday); Material counts from 0, Sunday.
  int get firstWeekday =>
      firstDayOfWeekIndex == 0 ? DateTime.sunday : firstDayOfWeekIndex;
}
