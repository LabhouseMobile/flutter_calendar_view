import 'package:flutter/material.dart';

import '../../calendar_view.dart';
import '../extensions.dart';

/// Internal reusable widget that renders a single month grid page.
class InternalMonthPage<T> extends StatefulWidget {
  const InternalMonthPage({
    required this.cellRatio,
    required this.showBorder,
    required this.borderSize,
    required this.cellBuilder,
    required this.selectedDate,
    required this.date,
    required this.controller,
    required this.width,
    required this.height,
    required this.onCellTap,
    required this.onDateLongPress,
    required this.onDateLongPressMoveUpdate,
    required this.onLongPressSelectionStateChange,
    required this.startDay,
    required this.physics,
    required this.hideDaysNotInMonth,
    required this.weekDays,
    Key? key,
    this.borderColor,
  }) : super(key: key);

  final double cellRatio;
  final bool showBorder;
  final double borderSize;
  final Color? borderColor;
  final CellBuilder<T> cellBuilder;
  final DateTime date;
  final EventController<T> controller;
  final double width;
  final double height;
  final CellTapCallback<T>? onCellTap;
  final DatePressCallback? onDateLongPress;
  final DateLongPressMoveUpdateCallback? onDateLongPressMoveUpdate;
  final ValueChanged<bool>? onLongPressSelectionStateChange;
  final WeekDays startDay;
  final ScrollPhysics physics;
  final bool hideDaysNotInMonth;
  final int weekDays;
  final DateTime? selectedDate;

  @override
  State<InternalMonthPage<T>> createState() => _InternalMonthPageState<T>();
}

class _InternalMonthPageState<T> extends State<InternalMonthPage<T>> {
  DateTime? _lastReportedDate;
  bool _isLongPressActive = false;

  @override
  void dispose() {
    _cancelLongPressTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monthDays = widget.date.datesOfMonths(
      startDay: widget.startDay,
      hideDaysNotInMonth: widget.hideDaysNotInMonth,
      showWeekends: widget.weekDays == 7,
    );
    final rowCount = (monthDays.length / widget.weekDays).ceil();

    final grid = SizedBox(
      width: widget.width,
      height: widget.height,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: widget.physics,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.weekDays,
          childAspectRatio: widget.cellRatio,
        ),
        itemCount: monthDays.length,
        shrinkWrap: true,
        itemBuilder: (context, index) {
          final events = widget.hideDaysNotInMonth &&
                  (monthDays[index].month != widget.date.month)
              ? <CalendarEventData<T>>[]
              : widget.controller.getEventsOnDay(monthDays[index]);
          final isSelected =
              widget.selectedDate?.compareWithoutTime(monthDays[index]) ??
                  false;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onCellTap?.call(events, monthDays[index]),
            child: Container(
              decoration: BoxDecoration(
                border: widget.showBorder
                    ? Border.all(
                        color: widget.borderColor ??
                            context.monthViewColors.cellBorderColor,
                        width: widget.borderSize,
                      )
                    : null,
              ),
              child: widget.cellBuilder(
                monthDays[index],
                events,
                monthDays[index].compareWithoutTime(DateTime.now()),
                monthDays[index].month == widget.date.month,
                isSelected,
                widget.hideDaysNotInMonth,
              ),
            ),
          );
        },
      ),
    );

    if (!_hasLongPressCallbacks) {
      return grid;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (details) => _handleLongPressStart(
        details,
        monthDays,
        rowCount,
      ),
      onLongPressMoveUpdate: (details) => _handleLongPressMoveUpdate(
        details,
        monthDays,
        rowCount,
      ),
      onLongPressEnd: (_) => _cancelLongPressTracking(),
      onLongPressCancel: _cancelLongPressTracking,
      child: grid,
    );
  }

  bool get _hasLongPressCallbacks {
    return widget.onDateLongPress != null ||
        widget.onDateLongPressMoveUpdate != null;
  }

  void _handleLongPressStart(
    LongPressStartDetails details,
    List<DateTime> monthDays,
    int rowCount,
  ) {
    if (!_hasLongPressCallbacks) return;

    _isLongPressActive = true;
    widget.onLongPressSelectionStateChange?.call(true);
    _lastReportedDate = null;
    _notifyLongPressDate(
      localPosition: details.localPosition,
      globalPosition: details.globalPosition,
      monthDays: monthDays,
      rowCount: rowCount,
      isMoveUpdate: false,
    );
  }

  void _handleLongPressMoveUpdate(
    LongPressMoveUpdateDetails details,
    List<DateTime> monthDays,
    int rowCount,
  ) {
    if (!_isLongPressActive) return;

    _notifyLongPressDate(
      localPosition: details.localPosition,
      globalPosition: details.globalPosition,
      monthDays: monthDays,
      rowCount: rowCount,
      isMoveUpdate: true,
      moveDetails: details,
    );
  }

  void _notifyLongPressDate({
    required Offset localPosition,
    required Offset globalPosition,
    required List<DateTime> monthDays,
    required int rowCount,
    required bool isMoveUpdate,
    LongPressMoveUpdateDetails? moveDetails,
  }) {
    final date = _getDateFromPosition(
      localPosition: localPosition,
      monthDays: monthDays,
      rowCount: rowCount,
    );

    if (date == null || date == _lastReportedDate) return;

    if (!isMoveUpdate) {
      widget.onDateLongPress?.call(date);
    } else if (widget.onDateLongPressMoveUpdate != null) {
      widget.onDateLongPressMoveUpdate!(
        date,
        moveDetails ??
            LongPressMoveUpdateDetails(
              globalPosition: globalPosition,
              localPosition: localPosition,
              offsetFromOrigin: Offset.zero,
              localOffsetFromOrigin: Offset.zero,
            ),
      );
    }

    _lastReportedDate = date;
  }

  DateTime? _getDateFromPosition({
    required Offset localPosition,
    required List<DateTime> monthDays,
    required int rowCount,
  }) {
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) return null;
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx >= size.width ||
        localPosition.dy >= size.height) {
      return null;
    }

    final columnWidth = size.width / widget.weekDays;
    final rowHeight = size.height / rowCount;
    final column = (localPosition.dx / columnWidth).floor();
    final row = (localPosition.dy / rowHeight).floor();
    final index = row * widget.weekDays + column;

    if (index < 0 || index >= monthDays.length) return null;
    return monthDays[index];
  }

  void _cancelLongPressTracking() {
    final wasLongPressActive = _isLongPressActive;
    _lastReportedDate = null;
    _isLongPressActive = false;
    if (wasLongPressActive) {
      widget.onLongPressSelectionStateChange?.call(false);
    }
  }
}
