import 'package:flutter/material.dart';

import '../enumerations.dart';
import '../extension.dart';
import '../widgets/responsive_widget.dart';
import '../widgets/schedule_view_widget.dart';
import 'create_event_page.dart';
import 'web/web_home_page.dart';

class ScheduleViewPageDemo extends StatefulWidget {
  @override
  _ScheduleViewPageDemoState createState() => _ScheduleViewPageDemoState();
}

class _ScheduleViewPageDemoState extends State<ScheduleViewPageDemo> {
  DateTime _focusDate = DateTime.now();
  int _jumpKey = 0;

  void _jumpToToday() {
    setState(() {
      _focusDate = DateTime.now();
      _jumpKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final translate = context.translate;

    return ResponsiveWidget(
      webWidget: WebHomePage(selectedView: CalendarView.schedule),
      mobileWidget: Scaffold(
        appBar: AppBar(title: Text(translate.scheduleView), centerTitle: true),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'jump_to_today_schedule_view',
              backgroundColor: appColors.primary,
              onPressed: _jumpToToday,
              child: Icon(Icons.keyboard_arrow_up, color: appColors.onPrimary),
            ),
            const SizedBox(height: 8),
            FloatingActionButton(
              heroTag: 'add_event_schedule_view',
              backgroundColor: appColors.primary,
              child: Icon(Icons.add, color: appColors.onPrimary),
              elevation: 8,
              onPressed: () => context.pushRoute(CreateEventPage()),
            ),
          ],
        ),
        body: ScheduleViewWidget(initialDay: _focusDate, jumpKey: _jumpKey),
      ),
    );
  }
}
