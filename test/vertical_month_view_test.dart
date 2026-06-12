import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VerticalMonthView jumpToMonth', () {
    testWidgets('lands exactly on a far month when minMonth defaults to 1970',
        (tester) async {
      final key = GlobalKey<VerticalMonthViewState<Object?>>();

      await tester.pumpWidget(
        _buildVerticalMonthView(
          key: key,
          initialMonth: DateTime(1980, 1, 1),
          maxMonth: DateTime(2030, 12, 31),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.jumpToMonth(DateTime(2026, 6, 1));
      await tester.pumpAndSettle();

      final expectedPage = (2026 - 1970) * 12 + (6 - 1);
      expect(key.currentState!.currentDate, DateTime(2026, 6));
      expect(key.currentState!.currentPage, expectedPage);
    });

    testWidgets('lands exactly on round-trip far jumps', (tester) async {
      final key = GlobalKey<VerticalMonthViewState<Object?>>();

      await tester.pumpWidget(
        _buildVerticalMonthView(
          key: key,
          initialMonth: DateTime(1980, 1, 1),
          maxMonth: DateTime(2030, 12, 31),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.jumpToMonth(DateTime(2026, 6, 1));
      await tester.pumpAndSettle();
      expect(key.currentState!.currentDate, DateTime(2026, 6));

      key.currentState!.jumpToMonth(DateTime(1995, 3, 1));
      await tester.pumpAndSettle();
      expect(key.currentState!.currentDate, DateTime(1995, 3));
      expect(
        key.currentState!.currentPage,
        (1995 - 1970) * 12 + (3 - 1),
      );

      key.currentState!.jumpToMonth(DateTime(1970, 1, 1));
      await tester.pumpAndSettle();
      expect(key.currentState!.currentDate, DateTime(1970, 1));
      expect(key.currentState!.currentPage, 0);
    });

    testWidgets(
        'brings every month (incl. the last) to the top in a small range',
        (tester) async {
      final key = GlobalKey<VerticalMonthViewState<Object?>>();

      await tester.pumpWidget(
        _buildVerticalMonthView(
          key: key,
          initialMonth: DateTime(2026, 5, 1),
          minMonth: DateTime(2026, 5, 1),
          maxMonth: DateTime(2026, 9, 30),
          viewportHeight: 600,
          stickyHeaderHeight: 0,
          withSeparator: true,
          shrinkHeaders: true,
          hideDaysNotInMonth: true,
          cellAspectRatio: 0.8,
        ),
      );
      await tester.pumpAndSettle();

      // Jump through every month, including the very last one which previously
      // could not be scrolled to the top.
      for (final month in [6, 7, 8, 9, 5]) {
        key.currentState!.jumpToMonth(DateTime(2026, month, 1), alignment: 0);
        await tester.pumpAndSettle();

        expect(key.currentState!.currentDate, DateTime(2026, month));
        expect(key.currentState!.currentPage, month - 5);

        final marker = find.text('in-$month');
        expect(marker, findsWidgets);

        // The target month's first in-month cell must sit at the top of the
        // viewport (above where the next month would begin).
        final targetTop = tester.getTopLeft(marker.first).dy;
        expect(targetTop, lessThan(120));

        for (final other in [5, 6, 7, 8, 9]) {
          if (other == month) continue;
          final otherFinder = find.text('in-$other');
          if (otherFinder.evaluate().isEmpty) continue;
          // Earlier months must be scrolled above; later months sit below.
          if (other < month) {
            expect(tester.getTopLeft(otherFinder.first).dy, lessThan(targetTop));
          } else {
            expect(
              tester.getTopLeft(otherFinder.first).dy,
              greaterThan(targetTop),
            );
          }
        }
      }
    });

    testWidgets('centers the target month in the viewport by default',
        (tester) async {
      final key = GlobalKey<VerticalMonthViewState<Object?>>();
      const viewportHeight = 600.0;

      await tester.pumpWidget(
        _buildVerticalMonthView(
          key: key,
          initialMonth: DateTime(2026, 5, 1),
          minMonth: DateTime(2026, 5, 1),
          maxMonth: DateTime(2026, 9, 30),
          viewportHeight: viewportHeight,
          stickyHeaderHeight: 0,
          withSeparator: true,
          shrinkHeaders: true,
          hideDaysNotInMonth: true,
          cellAspectRatio: 0.8,
        ),
      );
      await tester.pumpAndSettle();

      // Jump to the second month (June) - it should be centered, not at top.
      key.currentState!.jumpToMonth(DateTime(2026, 6, 1));
      await tester.pumpAndSettle();

      expect(key.currentState!.currentDate, DateTime(2026, 6));
      expect(key.currentState!.currentPage, 1);

      // The June cells should straddle the vertical middle of the viewport:
      // some above center, some below. This proves it is centered rather than
      // pinned to the top (where all cells would sit in the upper half).
      const center = viewportHeight / 2;
      final juneCells = find.text('in-6');
      expect(juneCells, findsWidgets);

      final ys = juneCells
          .evaluate()
          .map((e) => tester.getCenter(find.byWidget(e.widget)).dy)
          .toList();
      expect(ys.any((y) => y < center), isTrue,
          reason: 'expected some June cells above the viewport center');
      expect(ys.any((y) => y > center), isTrue,
          reason: 'expected some June cells below the viewport center');
    });

    testWidgets('jumpToToday returns to the current month from the last month',
        (tester) async {
      final key = GlobalKey<VerticalMonthViewState<Object?>>();
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);

      await tester.pumpWidget(
        _buildVerticalMonthView(
          key: key,
          initialMonth: currentMonth,
          minMonth: DateTime(now.year, now.month - 1),
          maxMonth: DateTime(now.year, now.month + 3, 28),
          viewportHeight: 600,
          stickyHeaderHeight: 0,
          withSeparator: true,
          shrinkHeaders: true,
          hideDaysNotInMonth: true,
          cellAspectRatio: 0.8,
        ),
      );
      await tester.pumpAndSettle();

      // Move to the last month first (the situation the user described).
      key.currentState!.jumpToPage(key.currentState!.currentPage + 10);
      await tester.pumpAndSettle();
      expect(key.currentState!.currentDate.isAfter(currentMonth), isTrue);

      // jumpToToday must bring us back to the current month.
      key.currentState!.jumpToToday();
      await tester.pumpAndSettle();
      expect(key.currentState!.currentDate, currentMonth);
    });

    testWidgets('throws when jumpToMonth receives date outside range',
        (tester) async {
      final key = GlobalKey<VerticalMonthViewState<Object?>>();

      await tester.pumpWidget(
        _buildVerticalMonthView(
          key: key,
          initialMonth: DateTime(1980, 1, 1),
          minMonth: DateTime(1970, 1, 1),
          maxMonth: DateTime(2030, 12, 31),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        () => key.currentState!.jumpToMonth(DateTime(1969, 12, 1)),
        throwsA('Invalid date selected.'),
      );
    });
  });
}

Widget _buildVerticalMonthView({
  required GlobalKey<VerticalMonthViewState<Object?>> key,
  required DateTime initialMonth,
  DateTime? minMonth,
  required DateTime maxMonth,
  double viewportHeight = 700,
  double stickyHeaderHeight = 36,
  bool withSeparator = false,
  bool shrinkHeaders = false,
  bool stickyMonthHeaders = false,
  bool hideDaysNotInMonth = false,
  double cellAspectRatio = 0.55,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 420,
        height: viewportHeight,
        child: VerticalMonthView<Object?>(
          key: key,
          width: 420,
          controller: EventController<Object?>(),
          monthViewStyle: MonthViewStyle(
            initialMonth: initialMonth,
            minMonth: minMonth,
            maxMonth: maxMonth,
            hideDaysNotInMonth: hideDaysNotInMonth,
            cellAspectRatio: cellAspectRatio,
            pagePhysics: NeverScrollableScrollPhysics(),
          ),
          stickyMonthHeaders: stickyMonthHeaders,
          stickyMonthHeaderHeight: stickyHeaderHeight,
          stickyMonthHeaderBuilder:
              shrinkHeaders ? (_) => const SizedBox.shrink() : null,
          monthSeparatorBuilder: withSeparator
              ? (above, below) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text('sep-${below.month}'),
                  )
              : null,
          monthViewBuilders: MonthViewBuilders<Object?>(
            headerBuilder:
                shrinkHeaders ? (_) => const SizedBox.shrink() : null,
            weekDaysHeaderBuilder:
                shrinkHeaders ? (_) => const SizedBox.shrink() : null,
            cellBuilder: (
              date,
              events,
              isToday,
              isInMonth,
              isSelected,
              hideDaysNotInMonth,
            ) {
              return Center(
                child: Text(
                  isInMonth ? 'in-${date.month}' : 'out-${date.day}',
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
