import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../calendar_view.dart';
import '_internal_month_page.dart';
import '../extensions.dart';

/// A continuously (vertically) scrolling month calendar.
///
/// Unlike [MonthView], which pages horizontally between months, this view
/// renders months stacked vertically in a single lazily-built scroll view.
/// Months are built on demand (via `super_sliver_list`) so the full
/// [MonthViewStyle.minMonth] to [MonthViewStyle.maxMonth] range can be huge
/// without freezing the UI.
///
/// Note: [MonthViewStyle.useAvailableVerticalSpace] is ignored here because
/// continuous scrolling has no fixed per-month viewport to fill.
class VerticalMonthView<T extends Object?> extends StatefulWidget {
  const VerticalMonthView({
    Key? key,
    this.monthViewStyle = const MonthViewStyle(),
    this.monthViewBuilders = const MonthViewBuilders(),
    this.monthViewThemeSettings = const MonthViewThemeSettings(),
    this.controller,
    this.width,
    this.selectedDate,
    this.multiDateSelectionRange = const {},
    this.multiDateSelectionColor,
    this.stickyMonthHeaders = true,
    this.stickyMonthHeaderHeight = 36,
    this.stickyMonthHeaderBuilder,
    this.monthSeparatorBuilder,
  }) : super(key: key);

  final EventController<T>? controller;
  final MonthViewStyle monthViewStyle;
  final MonthViewBuilders<T> monthViewBuilders;
  final MonthViewThemeSettings monthViewThemeSettings;
  final double? width;
  final DateTime? selectedDate;
  final Set<DateTime> multiDateSelectionRange;
  final Color? multiDateSelectionColor;

  /// When true (default), the label of the month currently at the top of the
  /// viewport stays pinned while scrolling and is pushed up by the next
  /// month's label (iOS-style section headers).
  ///
  /// When false, the per-month label simply scrolls away with its month.
  final bool stickyMonthHeaders;

  /// Height in logical pixels reserved for the per-month label.
  final double stickyMonthHeaderHeight;

  /// Builds the per-month label widget.
  ///
  /// Defaults to a left-aligned label using
  /// [MonthViewBuilders.headerStringBuilder] when provided, otherwise a
  /// localized `"<month> - <year>"` string.
  final DateWidgetBuilder? stickyMonthHeaderBuilder;

  /// Builds a separator rendered between two consecutive months.
  ///
  /// It receives the month immediately above the separator ([monthAbove]) and
  /// the month immediately below it ([monthBelow]). It is not shown above the
  /// first month. When null, no separator is rendered.
  ///
  /// The separator participates in scrolling and may have any height; it is
  /// independent of [stickyMonthHeaders].
  final Widget Function(DateTime monthAbove, DateTime monthBelow)?
      monthSeparatorBuilder;

  @override
  VerticalMonthViewState<T> createState() => VerticalMonthViewState<T>();
}

class VerticalMonthViewState<T extends Object?>
    extends State<VerticalMonthView<T>> {
  late DateTime _minDate;
  late DateTime _maxDate;
  late DateTime _currentDate;
  late int _currentIndex;
  int _totalMonths = 0;
  bool _isMultiDateSelectionInProgress = false;

  late ScrollController _scrollController;
  late ListController _listController;

  /// Key on the scroll area, used as the coordinate space for the sticky
  /// header overlay.
  final GlobalKey _viewportKey = GlobalKey();

  /// Per-month-index keys for the inline month labels. Only labels that are
  /// currently built (visible) resolve to a context; used to drive the
  /// sticky-header push effect without any offset table.
  final Map<int, GlobalKey> _headerKeys = {};

  late double _width;
  late double _cellWidth;
  late double _cellHeight;

  DateTime? _selectedDate;
  late CellBuilder<T> _cellBuilder;
  late WeekDayBuilder _weekBuilder;
  late DateWidgetBuilder _headerBuilder;
  EventController<T>? _controller;
  late VoidCallback _reloadCallback;
  late MonthViewStyle _monthViewStyle = widget.monthViewStyle;
  late MonthViewBuilders<T> _monthViewBuilders = widget.monthViewBuilders;
  late MonthViewThemeSettings _monthViewThemeSettings =
      widget.monthViewThemeSettings;

  @override
  void initState() {
    super.initState();
    _reloadCallback = _reload;

    _setDateRange();
    _currentDate = (_monthViewStyle.initialMonth ?? DateTime.now()).withoutTime;
    _regulateCurrentDate();
    _selectedDate = widget.selectedDate?.withoutTime;
    _assignBuilders();

    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _listController = ListController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newController = widget.controller ??
        CalendarControllerProvider.of<T>(context).controller;
    if (newController != _controller) {
      _controller = newController;
      _controller!
        ..removeListener(_reloadCallback)
        ..addListener(_reloadCallback);
    }

    updateViewDimensions();
    _scheduleScrollSyncToCurrentIndex();
  }

  @override
  void didUpdateWidget(VerticalMonthView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newController = widget.controller ??
        CalendarControllerProvider.of<T>(context).controller;
    _monthViewStyle = widget.monthViewStyle;
    _monthViewBuilders = widget.monthViewBuilders;
    _monthViewThemeSettings = widget.monthViewThemeSettings;

    if (newController != _controller) {
      _controller?.removeListener(_reloadCallback);
      _controller = newController;
      _controller?.addListener(_reloadCallback);
    }

    if (_monthViewStyle.minMonth != oldWidget.monthViewStyle.minMonth ||
        _monthViewStyle.maxMonth != oldWidget.monthViewStyle.maxMonth) {
      _setDateRange();
      _regulateCurrentDate();
    }

    _assignBuilders();

    if (widget.selectedDate != null) {
      _selectedDate = widget.selectedDate?.withoutTime;
    } else if (oldWidget.selectedDate != null) {
      _selectedDate = oldWidget.selectedDate?.withoutTime;
    }

    updateViewDimensions();
    _scheduleScrollSyncToCurrentIndex();
  }

  @override
  void dispose() {
    _controller?.removeListener(_reloadCallback);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _currentDate.datesOfWeek(
      start: _monthViewStyle.startDay,
      showWeekEnds: _monthViewStyle.showWeekends,
    );

    return SafeAreaWrapper(
      option: _monthViewStyle.safeAreaOption,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _width,
              child: _headerBuilder(_currentDate),
            ),
            if (_monthViewBuilders.weekDaysHeaderBuilder != null)
              _monthViewBuilders.weekDaysHeaderBuilder!(weekDays)
            else
              SizedBox(
                width: _width,
                child: Row(
                  children: List.generate(
                    _monthViewStyle.showWeekends ? 7 : 5,
                    (index) => Expanded(
                      child: SizedBox(
                        width: _cellWidth,
                        child: _weekBuilder(weekDays[index].weekday - 1),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                key: _viewportKey,
                children: [
                  SuperListView.builder(
                    listController: _listController,
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    physics: _isMultiDateSelectionInProgress
                        ? const NeverScrollableScrollPhysics()
                        : (_monthViewStyle.pageViewPhysics ??
                            const ClampingScrollPhysics()),
                    itemCount: _totalMonths,
                    itemBuilder: (context, index) => _buildMonthBlock(index),
                  ),
                  if (widget.stickyMonthHeaders)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedBuilder(
                        animation: Listenable.merge(
                          [_scrollController, _listController],
                        ),
                        builder: (context, _) => _buildStickyOverlay(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One month block: the (inline) label followed by the month grid.
  Widget _buildMonthBlock(int index) {
    final date = DateTime(_minDate.year, _minDate.month + index);
    final gridHeight = _monthGridHeight(index);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (index > 0 && widget.monthSeparatorBuilder != null)
          widget.monthSeparatorBuilder!(
            DateTime(_minDate.year, _minDate.month + index - 1),
            date,
          ),
        SizedBox(
          key: _headerKeyFor(index),
          width: _width,
          height: widget.stickyMonthHeaderHeight,
          child: _stickyHeaderBuilder(date),
        ),
        SizedBox(
          height: gridHeight,
          width: _width,
          child: InternalMonthPage<T>(
            key: ValueKey(date.toIso8601String()),
            onCellTap: _handleCellTap,
            onDateLongPress: _monthViewBuilders.onDateLongPress,
            onDateLongPressMoveUpdate:
                _monthViewBuilders.onDateLongPressMoveUpdate,
            onLongPressSelectionStateChange:
                _handleLongPressSelectionStateChange,
            width: _width,
            height: gridHeight,
            controller: controller,
            borderColor: _monthViewStyle.borderColor,
            borderSize: _monthViewStyle.borderSize,
            cellBuilder: _cellBuilder,
            selectedDate: _selectedDate,
            cellRatio: _monthViewStyle.cellAspectRatio,
            date: date,
            showBorder: _monthViewStyle.showBorder,
            startDay: _monthViewStyle.startDay,
            physics: const NeverScrollableScrollPhysics(),
            hideDaysNotInMonth: _monthViewStyle.hideDaysNotInMonth,
            weekDays: _monthViewStyle.showWeekends ? 7 : 5,
          ),
        ),
      ],
    );
  }

  Widget _buildStickyOverlay() {
    if (!_listController.isAttached || !_scrollController.hasClients) {
      return const SizedBox.shrink();
    }

    final visible = _listController.visibleRange;
    if (visible == null) return const SizedBox.shrink();

    final topIndex = visible.$1.clamp(0, _totalMonths - 1);
    final month = DateTime(_minDate.year, _minDate.month + topIndex);

    // Push the pinned label up as the next month's (inline) label approaches
    // the top edge, measured from the already-built next header.
    final translateY = _stickyPushOffset(topIndex);

    return Transform.translate(
      offset: Offset(0, translateY),
      child: SizedBox(
        width: _width,
        height: widget.stickyMonthHeaderHeight,
        child: _stickyHeaderBuilder(month),
      ),
    );
  }

  /// Returns a negative vertical offset that slides the pinned header up as the
  /// next month's inline header reaches the top, or `0` otherwise.
  double _stickyPushOffset(int topIndex) {
    final nextIndex = topIndex + 1;
    if (nextIndex >= _totalMonths) return 0;

    final viewportBox =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final nextHeaderBox = _headerKeys[nextIndex]
        ?.currentContext
        ?.findRenderObject() as RenderBox?;
    if (viewportBox == null ||
        nextHeaderBox == null ||
        !viewportBox.attached ||
        !nextHeaderBox.attached) {
      return 0;
    }

    final nextHeaderTop =
        viewportBox.globalToLocal(nextHeaderBox.localToGlobal(Offset.zero)).dy;
    if (nextHeaderTop >= widget.stickyMonthHeaderHeight) return 0;

    return (nextHeaderTop - widget.stickyMonthHeaderHeight)
        .clamp(-widget.stickyMonthHeaderHeight, 0.0);
  }

  GlobalKey _headerKeyFor(int index) =>
      _headerKeys.putIfAbsent(index, () => GlobalKey());

  EventController<T> get controller {
    if (_controller == null) {
      throw "EventController is not initialized yet.";
    }

    return _controller!;
  }

  /// Index (0-based) of the month currently at the top of the viewport.
  int get currentPage => _currentIndex;

  /// Month currently at the top of the viewport.
  DateTime get currentDate => DateTime(_currentDate.year, _currentDate.month);

  /// Animate to the next month.
  void nextPage({Duration? duration, Curve? curve}) {
    if (_currentIndex >= _totalMonths - 1) return;
    animateToPage(_currentIndex + 1, duration: duration, curve: curve);
  }

  /// Animate to the previous month.
  void previousPage({Duration? duration, Curve? curve}) {
    if (_currentIndex <= 0) return;
    animateToPage(_currentIndex - 1, duration: duration, curve: curve);
  }

  /// Jump (without animation) to month at [page] index.
  void jumpToPage(int page) {
    final normalizedPage = page.clamp(0, _totalMonths - 1);
    _updateCurrentPage(normalizedPage);
    if (!_listController.isAttached || !_scrollController.hasClients) {
      _scheduleScrollSyncToCurrentIndex();
      return;
    }
    _listController.jumpToItem(
      index: normalizedPage,
      scrollController: _scrollController,
      alignment: 0,
    );
  }

  /// Animate to month at [page] index.
  Future<void> animateToPage(
    int page, {
    Duration? duration,
    Curve? curve,
  }) async {
    final normalizedPage = page.clamp(0, _totalMonths - 1);
    if (!_listController.isAttached || !_scrollController.hasClients) {
      _updateCurrentPage(normalizedPage);
      _scheduleScrollSyncToCurrentIndex();
      return;
    }
    _listController.animateToItem(
      index: normalizedPage,
      scrollController: _scrollController,
      alignment: 0,
      duration: (_) => duration ?? _monthViewStyle.pageTransitionDuration,
      curve: (_) => curve ?? _monthViewStyle.pageTransitionCurve,
    );
  }

  /// Jump (without animation) to the given [month].
  void jumpToMonth(DateTime month) {
    if (month.isBefore(_minDate) || month.isAfter(_maxDate)) {
      throw "Invalid date selected.";
    }
    jumpToPage(_minDate.getMonthDifference(month) - 1);
  }

  /// Animate to the given [month].
  Future<void> animateToMonth(
    DateTime month, {
    Duration? duration,
    Curve? curve,
  }) async {
    if (month.isBefore(_minDate) || month.isAfter(_maxDate)) {
      throw "Invalid date selected.";
    }
    await animateToPage(
      _minDate.getMonthDifference(month) - 1,
      duration: duration,
      curve: curve,
    );
  }

  void _onScroll() {
    if (!_listController.isAttached) return;
    final visible = _listController.visibleRange;
    if (visible == null) return;
    _updateCurrentPage(visible.$1.clamp(0, _totalMonths - 1));
  }

  void _updateCurrentPage(int newIndex) {
    if (newIndex == _currentIndex) return;
    if (!mounted) {
      _currentIndex = newIndex;
      _currentDate = DateTime(_minDate.year, _minDate.month + newIndex);
      return;
    }
    setState(() {
      _currentIndex = newIndex;
      _currentDate = DateTime(_minDate.year, _minDate.month + newIndex);
    });
    _monthViewBuilders.onPageChange?.call(_currentDate, _currentIndex);
  }

  void _scheduleScrollSyncToCurrentIndex() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_listController.isAttached ||
          !_scrollController.hasClients) {
        return;
      }
      _listController.jumpToItem(
        index: _currentIndex.clamp(0, _totalMonths - 1),
        scrollController: _scrollController,
        alignment: 0,
      );
    });
  }

  bool _isSameDate(DateTime? first, DateTime? second) {
    if (first == null || second == null) {
      return first == second;
    }

    return first.withoutTime.compareWithoutTime(second.withoutTime);
  }

  void _reload() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleLongPressSelectionStateChange(bool isInProgress) {
    if (_isMultiDateSelectionInProgress == isInProgress || !mounted) return;
    setState(() {
      _isMultiDateSelectionInProgress = isInProgress;
    });
  }

  void updateViewDimensions() {
    _width = widget.width ?? MediaQuery.of(context).size.width;
    final columnCount = _monthViewStyle.showWeekends ? 7 : 5;
    _cellWidth = _width / columnCount;
    _cellHeight = _cellWidth / _monthViewStyle.cellAspectRatio;
  }

  double _monthGridHeight(int index) {
    final monthDate = DateTime(_minDate.year, _minDate.month + index);
    final dates = monthDate.datesOfMonths(
      startDay: _monthViewStyle.startDay,
      hideDaysNotInMonth: _monthViewStyle.hideDaysNotInMonth,
      showWeekends: _monthViewStyle.showWeekends,
    );
    final columnCount = _monthViewStyle.showWeekends ? 7 : 5;
    final rows = (dates.length / columnCount).ceil();
    return _cellHeight * rows;
  }

  void _assignBuilders() {
    _cellBuilder = _monthViewBuilders.cellBuilder ?? _defaultCellBuilder;
    _weekBuilder = _monthViewBuilders.weekDayBuilder ?? _defaultWeekDayBuilder;
    _headerBuilder = _monthViewBuilders.headerBuilder ?? _defaultHeaderBuilder;
  }

  void _regulateCurrentDate() {
    if (_currentDate.isBefore(_minDate)) {
      _currentDate = _minDate;
    } else if (_currentDate.isAfter(_maxDate)) {
      _currentDate = _maxDate;
    }

    _currentIndex = _minDate.getMonthDifference(_currentDate) - 1;
  }

  void _setDateRange() {
    _minDate =
        (_monthViewStyle.minMonth ?? CalendarConstants.epochDate).withoutTime;
    _maxDate =
        (_monthViewStyle.maxMonth ?? CalendarConstants.maxDate).withoutTime;

    assert(
      _minDate.isBefore(_maxDate),
      'Minimum date should be less than maximum date.\n'
      'Provided minimum date: $_minDate, maximum date: $_maxDate',
    );
    _totalMonths = _maxDate.getMonthDifference(_minDate);
  }

  Widget _stickyHeaderBuilder(DateTime date) {
    return widget.stickyMonthHeaderBuilder?.call(date) ??
        _defaultStickyMonthHeaderBuilder(date);
  }

  Widget _defaultStickyMonthHeaderBuilder(DateTime date) {
    final title = _monthViewBuilders.headerStringBuilder?.call(date) ??
        "${PackageStrings.localizeNumber(date.month)} - ${PackageStrings.localizeNumber(date.year)}";
    return Container(
      color: context.monthViewColors.headerBackgroundColor,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        title,
        style: TextStyle(
          color: context.monthViewColors.headerTextColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _defaultHeaderBuilder(DateTime date) {
    return MonthPageHeader(
      showPreviousIcon: date != _minDate,
      showNextIcon: date != _maxDate,
      onTitleTapped: () async {
        if (_monthViewBuilders.onHeaderTitleTap != null) {
          await _monthViewBuilders.onHeaderTitleTap!(date);
        } else {
          final selectedDate = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: _minDate,
            lastDate: _maxDate,
            locale: Locale(PackageStrings.selectedLocale),
          );

          if (selectedDate == null) return;
          jumpToMonth(selectedDate);
        }
      },
      onPreviousMonth: previousPage,
      date: date,
      dateStringBuilder: _monthViewBuilders.headerStringBuilder,
      onNextMonth: nextPage,
      headerStyle: _monthViewThemeSettings.headerStyle ??
          HeaderStyle(
            decoration: BoxDecoration(
              color: context.monthViewColors.headerBackgroundColor,
            ),
            leftIconConfig: IconDataConfig(
              color: context.monthViewColors.headerIconColor,
            ),
            rightIconConfig: IconDataConfig(
              color: context.monthViewColors.headerIconColor,
            ),
            headerTextStyle: TextStyle(
              color: context.monthViewColors.headerTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
    );
  }

  Widget _defaultWeekDayBuilder(int index) {
    final themeColors = context.monthViewColors;
    return WeekDayTile(
      dayIndex: index,
      weekDayStringBuilder: _monthViewBuilders.weekDayStringBuilder,
      displayBorder: _monthViewStyle.showWeekTileBorder,
      borderColor: themeColors.weekDayBorderColor,
      backgroundColor: themeColors.weekDayTileColor,
      textStyle: _monthViewThemeSettings.weekDayTextStyle,
    );
  }

  Widget _defaultCellBuilder(
    DateTime date,
    List<CalendarEventData<T>> events,
    bool isToday,
    bool isInMonth,
    bool isSelected,
    bool hideDaysNotInMonth,
  ) {
    final normalizedDate = date.withoutTime;
    final isMultiSelected = widget.multiDateSelectionRange.any(
      (selectedDate) => selectedDate.withoutTime == normalizedDate,
    );
    final color = isMultiSelected ? widget.multiDateSelectionColor : null;
    final themeColor = context.monthViewColors;
    final shouldHighlight = isSelected || isToday;
    final highlightedTitleColor = isSelected
        ? _monthViewThemeSettings.selectedTitleColor
        : hideDaysNotInMonth
            ? _monthViewThemeSettings.cellsNotInMonthHighlightedTitleColor
            : _monthViewThemeSettings.cellsInMonthHighlightedTitleColor;
    final highlightColor = isSelected
        ? _monthViewThemeSettings.selectedHighlightColor
        : hideDaysNotInMonth
            ? themeColor.cellHighlightColor
            : _monthViewThemeSettings.cellsInMonthHighlightColor;
    final highlightRadius = isSelected
        ? _monthViewThemeSettings.selectedHighlightRadius
        : hideDaysNotInMonth
            ? _monthViewThemeSettings.cellsNotInMonthHighlightRadius
            : _monthViewThemeSettings.cellsInMonthHighlightRadius;

    if (hideDaysNotInMonth) {
      return FilledCell<T>(
        date: date,
        shouldHighlight: shouldHighlight,
        backgroundColor: isInMonth
            ? themeColor.cellInMonthColor
            : themeColor.cellNotInMonthColor,
        events: events,
        isInMonth: isInMonth,
        onTileTap: _monthViewBuilders.onEventTap,
        onTileDoubleTap: _monthViewBuilders.onEventDoubleTap,
        onTileLongTap: _monthViewBuilders.onEventLongTap,
        onTileTapDetails: _monthViewBuilders.onEventTapDetails,
        onTileDoubleTapDetails: _monthViewBuilders.onEventDoubleTapDetails,
        onTileLongTapDetails: _monthViewBuilders.onEventLongTapDetails,
        dateStringBuilder: _monthViewBuilders.dateStringBuilder,
        hideDaysNotInMonth: hideDaysNotInMonth,
        titleColor: themeColor.cellTextColor,
        highlightColor: highlightColor,
        tileColor: themeColor.weekDayTileColor,
        highlightRadius: highlightRadius,
        highlightedTitleColor: highlightedTitleColor,
        multipleDateSelectionColor: color,
      );
    }
    return FilledCell<T>(
      date: date,
      shouldHighlight: shouldHighlight,
      backgroundColor: isInMonth
          ? themeColor.cellInMonthColor
          : themeColor.cellNotInMonthColor,
      events: events,
      onTileTap: _monthViewBuilders.onEventTap,
      onTileLongTap: _monthViewBuilders.onEventLongTap,
      onTileTapDetails: _monthViewBuilders.onEventTapDetails,
      onTileDoubleTapDetails: _monthViewBuilders.onEventDoubleTapDetails,
      onTileLongTapDetails: _monthViewBuilders.onEventLongTapDetails,
      dateStringBuilder: _monthViewBuilders.dateStringBuilder,
      onTileDoubleTap: _monthViewBuilders.onEventDoubleTap,
      hideDaysNotInMonth: hideDaysNotInMonth,
      titleColor: isInMonth
          ? themeColor.cellTextColor
          : themeColor.cellTextColor.withAlpha(150),
      highlightedTitleColor: highlightedTitleColor,
      highlightRadius: highlightRadius,
      tileColor: _monthViewThemeSettings.cellsInMonthTileColor,
      highlightColor: highlightColor,
      multipleDateSelectionColor: color,
    );
  }

  void _handleCellTap(List<CalendarEventData<T>> events, DateTime date) {
    if (widget.selectedDate == null &&
        !_isSameDate(_selectedDate, date.withoutTime) &&
        mounted) {
      setState(() {
        _selectedDate = date.withoutTime;
      });
    }
    _monthViewBuilders.onCellTap?.call(events, date);
  }
}
