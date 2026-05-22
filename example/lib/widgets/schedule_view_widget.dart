import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';

import '../extension.dart';
import '../pages/create_event_page.dart';
import '../pages/event_details_page.dart';

class ScheduleViewWidget extends StatelessWidget {
  final double? width;
  final DateTime? initialDay;
  final int jumpKey;

  const ScheduleViewWidget({
    super.key,
    this.width,
    this.initialDay,
    this.jumpKey = 0,
  });

  String _formatTime(TimeOfDay time) =>
      time.getTimeInFormat(TimeStampFormat.parse_12);

  String _buildTimeLabel(CalendarEventData event) {
    if (event.isFullDayEvent) return 'All day';
    final start = event.startTime;
    final end = event.endTime;
    if (start != null && end != null) {
      return '${_formatTime(start)} – ${_formatTime(end)}';
    }
    if (start != null) return _formatTime(start);
    return 'All day';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white.withAlpha(222) : Colors.black87;
    final textSecondary = isDark ? Colors.white.withAlpha(153) : Colors.black54;

    return Container(
      width: width,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ScheduleView(
        key: ValueKey(jumpKey),
        initialDay: initialDay ?? DateTime.now(),

        // ── Month header ────────────────────────────────────────────────
        monthHeaderBuilder: (date) {
          const months = [
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  '${months[date.month - 1]} ${date.year}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: isDark
                    ? Colors.white.withAlpha(30)
                    : Colors.black.withAlpha(15),
              ),
            ],
          );
        },

        // ── Date column with today highlight ─────────────────────────────
        dayDetectorBuilder: (date, events) {
          const abbrs = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final now = DateTime.now();
          final isToday =
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
          final accentColor = isToday ? Colors.blue : Colors.transparent;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${date.day}/${date.month}/${date.year}'),
                duration: const Duration(seconds: 1),
              ),
            ),
            onLongPress: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Long pressed ${date.day}/${date.month}/${date.year}',
                ),
                duration: const Duration(seconds: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    abbrs[(date.weekday - 1).clamp(0, 6)],
                    style: TextStyle(
                      fontSize: 11,
                      color: isToday ? Colors.blue : textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                        color: isToday ? Colors.white : textPrimary,
                      ),
                    ),
                  ),
                  if (events.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: events
                          .take(3)
                          .map(
                            (e) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: e.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },

        eventTileBuilder: (event, date) {
          final timeLabel = _buildTimeLabel(event);
          final tileColor = event.color.withAlpha(isDark ? 45 : 28);
          final timeColor = HSLColor.fromColor(event.color)
              .withLightness(
                (HSLColor.fromColor(event.color).lightness - 0.1).clamp(
                  0.0,
                  1.0,
                ),
              )
              .toColor();

          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetailsPage(event: event, date: date),
              ),
            ),
            onDoubleTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CreateEventPage(event: event)),
            ),
            onLongPress: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(event.title),
                duration: const Duration(seconds: 1),
              ),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: event.color, width: 4)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Time + badges row
                          Row(
                            children: [
                              Text(
                                timeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? event.color.withAlpha(220)
                                      : timeColor,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              if (event.isRecurringEvent) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.repeat,
                                  size: 11,
                                  color: isDark
                                      ? event.color.withAlpha(200)
                                      : timeColor,
                                ),
                              ],
                              if (event.isRangingEvent) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.date_range,
                                  size: 11,
                                  color: isDark
                                      ? event.color.withAlpha(200)
                                      : timeColor,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Title
                          Text(
                            event.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Description preview
                          if (event.description?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 2),
                            Text(
                              event.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: textSecondary.withAlpha(120),
                    ),
                  ],
                ),
              ),
            ),
          );
        },

        // ── Empty day placeholder ────────────────────────────────────────
        emptyTextWidget: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(
            'No events',
            style: TextStyle(
              fontSize: 13,
              color: textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),

        // ── Navigation callbacks ─────────────────────────────────────────
        onEventTap: (events, date) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsPage(event: events.first, date: date),
          ),
        ),
        onEventDoubleTap: (events, date) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateEventPage(event: events.first),
          ),
        ),
        onDateTap: (date) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${date.day}/${date.month}/${date.year}'),
            duration: const Duration(seconds: 1),
          ),
        ),
        onDateLongPress: (date) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Long pressed ${date.day}/${date.month}/${date.year}',
            ),
            duration: const Duration(seconds: 1),
          ),
        ),
      ),
    );
  }
}
