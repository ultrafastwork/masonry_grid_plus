// Pins the behavior of MasonryGridView when its column layout changes while
// the user is scrolled away from the top (rotation, split-screen, window
// resize).
//
// These tests describe the observable contract of each
// MasonryRelayoutBehavior, not the algorithm, so they must keep passing if the
// relayout strategy is ever replaced.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_grid_plus/masonry_grid_plus.dart';

import '../../masonry_reference.dart';

const _itemCount = 2000;
const _spacing = 4.0;
const _width = 800.0;
const _height = 600.0;

/// Compares every built tile, including the cache area, against [reference].
void _expectReferenceLayout(
  List<Offset> reference,
  double scrollOffset, {
  required String reason,
}) {
  final rects = builtTileRects();
  expect(rects, isNotEmpty, reason: reason);
  for (final MapEntry(key: index, value: rect) in rects.entries) {
    expect(
      rect.left,
      moreOrLessEquals(reference[index].dx, epsilon: 1e-6),
      reason: '#$index x, $reason',
    );
    expect(
      rect.top,
      moreOrLessEquals(reference[index].dy - scrollOffset, epsilon: 1e-6),
      reason: '#$index y at scroll offset $scrollOffset, $reason',
    );
  }
}

/// Checks that no two built tiles overlap, and that the tiles of each column
/// are separated by exactly the spacing.
void _expectNoOverlapsOrGaps({required String reason}) {
  final byColumn = <int, List<MapEntry<int, Rect>>>{};
  for (final entry in builtTileRects().entries) {
    byColumn.putIfAbsent(entry.value.left.round(), () => []).add(entry);
  }
  for (final column in byColumn.values) {
    column.sort((a, b) => a.value.top.compareTo(b.value.top));
    for (var i = 1; i < column.length; i++) {
      final previous = column[i - 1];
      final current = column[i];
      expect(
        current.value.top - previous.value.bottom,
        moreOrLessEquals(_spacing, epsilon: 1e-6),
        reason:
            '#${previous.key} -> #${current.key} at x='
            '${current.value.left}, $reason',
      );
    }
  }
}

/// The smallest index among tiles intersecting the viewport, and its top.
(int, double) _firstVisible() {
  final visible = builtTileRects().entries
      .where((e) => e.value.bottom > 0 && e.value.top < _height)
      .toList();
  final first = visible.reduce((a, b) => a.key < b.key ? a : b);
  return (first.key, first.value.top);
}

/// Drags by [dragDelta] until the scroll offset stops changing or [until]
/// returns true, and returns the number of frames in which the tiles visible
/// before and after the frame did not all move by the same amount.
///
/// Comparing tiles with each other rather than with the scroll offset keeps
/// scroll offset corrections, which move the content and the scroll offset
/// together, from counting as jumps.
Future<int> _dragCountingJumps(
  WidgetTester tester,
  ScrollController controller,
  Offset dragDelta, {
  bool Function()? until,
  void Function()? eachFrame,
}) async {
  var framesWithJumps = 0;
  for (var frame = 0; frame < 400; frame++) {
    if (until?.call() ?? false) {
      break;
    }
    final previousOffset = controller.offset;
    final previous = builtTileRects();
    await tester.drag(find.byType(MasonryGridView), dragDelta);
    await tester.pump();
    eachFrame?.call();
    var jumped = false;
    double? commonDelta;
    for (final MapEntry(key: index, value: rect) in builtTileRects().entries) {
      final before = previous[index];
      if (before == null || before.bottom < 0 || before.top > _height) {
        continue;
      }
      final delta = rect.top - before.top;
      commonDelta ??= delta;
      if ((rect.left - before.left).abs() > 0.01 ||
          (delta - commonDelta).abs() > 0.01) {
        jumped = true;
      }
    }
    if (jumped) {
      framesWithJumps++;
    }
    if (controller.offset == previousOffset) {
      break;
    }
  }
  return framesWithJumps;
}

/// A tile that counts how many times its state was created.
class _StatefulTile extends StatefulWidget {
  const _StatefulTile({super.key, required this.index, required this.onInit});

  final int index;
  final void Function(int index) onInit;

  @override
  State<_StatefulTile> createState() => _StatefulTileState();
}

class _StatefulTileState extends State<_StatefulTile> {
  @override
  void initState() {
    super.initState();
    widget.onInit(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(aspectRatio: masonryTestRatioOf(widget.index));
  }
}

class _Harness {
  _Harness(this.tester, this.behavior);

  final WidgetTester tester;
  final MasonryRelayoutBehavior behavior;
  final controller = ScrollController();
  late StateSetter _setState;
  int _crossAxisCount = 4;
  double _mainAxisSpacing = _spacing;
  int builds = 0;

  Future<void> pump({
    required int crossAxisCount,
    Widget Function(int index)? tileBuilder,
  }) async {
    _crossAxisCount = crossAxisCount;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            _setState = setState;
            return MasonryGridView.count(
              controller: controller,
              crossAxisCount: _crossAxisCount,
              mainAxisSpacing: _mainAxisSpacing,
              crossAxisSpacing: _spacing,
              relayoutBehavior: behavior,
              itemCount: _itemCount,
              itemBuilder: (context, index) {
                builds++;
                return tileBuilder?.call(index) ??
                    AspectRatio(
                      key: ValueKey(index),
                      aspectRatio: masonryTestRatioOf(index),
                    );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> setCrossAxisCount(int value) async {
    _setState(() => _crossAxisCount = value);
    await tester.pump();
  }

  Future<void> setMainAxisSpacing(double value) async {
    _setState(() => _mainAxisSpacing = value);
    await tester.pump();
  }

  Future<void> jumpTo(double offset) async {
    controller.jumpTo(offset);
    await tester.pump();
  }

  List<Offset> reference(
    int crossAxisCount, {
    double mainAxisSpacing = _spacing,
  }) => referenceMasonryLayout(
    itemCount: _itemCount,
    crossAxisCount: crossAxisCount,
    crossAxisExtent: _width,
    spacing: _spacing,
    mainAxisSpacing: mainAxisSpacing,
  );
}

const _changes = [
  (4, 3, 100.0), // Still near the top: the first child is index 0.
  (4, 3, 6000.0),
  (4, 3, 20000.0),
  (3, 5, 15000.0),
  (5, 2, 9000.0),
  (2, 6, 30000.0),
];

void main() {
  group('MasonryRelayoutBehavior.exact', () {
    const behavior = MasonryRelayoutBehavior.exact;

    for (final (from, to, offset) in _changes) {
      testWidgets('crossAxisCount $from -> $to at offset $offset keeps an '
          'exact top-down masonry layout', (tester) async {
        final harness = _Harness(tester, behavior);
        addTearDown(harness.controller.dispose);
        await harness.pump(crossAxisCount: from);
        await harness.jumpTo(offset);
        _expectReferenceLayout(
          harness.reference(from),
          harness.controller.offset,
          reason: 'before the change',
        );

        await harness.setCrossAxisCount(to);
        expect(tester.takeException(), isNull);

        final reference = harness.reference(to);
        _expectReferenceLayout(
          reference,
          harness.controller.offset,
          reason: 'right after the change',
        );

        // Scrolling forward, jumping back, and dragging up to the top must
        // keep matching the layout a fresh grid would have produced.
        for (final delta in [3000.0, -1500.0, 800.0]) {
          await harness.jumpTo(
            (harness.controller.offset + delta).clamp(
              0,
              harness.controller.position.maxScrollExtent,
            ),
          );
          _expectReferenceLayout(
            reference,
            harness.controller.offset,
            reason: 'after jumping by $delta',
          );
        }
        while (harness.controller.offset > 0) {
          await tester.drag(find.byType(MasonryGridView), const Offset(0, 400));
          await tester.pump();
          _expectReferenceLayout(
            reference,
            harness.controller.offset,
            reason: 'while dragging back to the top',
          );
        }
        expect(tester.takeException(), isNull);
        final first = tester.getTopLeft(find.byKey(const ValueKey(0)));
        expect(first.dx, moreOrLessEquals(0));
        expect(first.dy, moreOrLessEquals(0));
      });
    }

    testWidgets('changing the crossAxisCount back restores the original '
        'layout', (tester) async {
      final harness = _Harness(tester, behavior);
      addTearDown(harness.controller.dispose);
      await harness.pump(crossAxisCount: 4);
      await harness.jumpTo(12000);

      for (final count in [3, 4, 2, 4]) {
        await harness.setCrossAxisCount(count);
        expect(tester.takeException(), isNull);
        _expectReferenceLayout(
          harness.reference(count),
          harness.controller.offset,
          reason: 'after switching to $count columns',
        );
      }
    });

    testWidgets('changing the mainAxisSpacing keeps an exact layout', (
      tester,
    ) async {
      final harness = _Harness(tester, behavior);
      addTearDown(harness.controller.dispose);
      await harness.pump(crossAxisCount: 4);
      await harness.jumpTo(12000);

      await harness.setMainAxisSpacing(12);
      final reference = harness.reference(4, mainAxisSpacing: 12);
      _expectReferenceLayout(
        reference,
        harness.controller.offset,
        reason: 'after the change',
      );
      final jumps = await _dragCountingJumps(
        tester,
        harness.controller,
        const Offset(0, 400),
        eachFrame: () => _expectReferenceLayout(
          reference,
          harness.controller.offset,
          reason: 'while dragging back to the top',
        ),
      );
      expect(jumps, 0);
    });
  });

  group('MasonryRelayoutBehavior.anchored', () {
    const behavior = MasonryRelayoutBehavior.anchored;

    for (final (from, to, offset) in _changes) {
      testWidgets('crossAxisCount $from -> $to at offset $offset keeps tiles '
          'stable and settles to the exact layout at the top', (tester) async {
        final harness = _Harness(tester, behavior);
        addTearDown(harness.controller.dispose);
        await harness.pump(crossAxisCount: from);
        await harness.jumpTo(offset);

        await harness.setCrossAxisCount(to);
        expect(tester.takeException(), isNull);
        _expectNoOverlapsOrGaps(reason: 'right after the change');

        // Scrolling forward moves nothing on screen.
        expect(
          await _dragCountingJumps(
            tester,
            harness.controller,
            const Offset(0, -300),
            until: () => harness.controller.offset > offset + 3000,
            eachFrame: () =>
                _expectNoOverlapsOrGaps(reason: 'while scrolling forward'),
          ),
          0,
        );

        // Scrolling back to the top moves the tiles on screen at most once,
        // when switching back to the exact layout.
        final jumps = await _dragCountingJumps(
          tester,
          harness.controller,
          const Offset(0, 300),
          eachFrame: () =>
              _expectNoOverlapsOrGaps(reason: 'while scrolling back'),
        );
        expect(jumps, lessThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
        expect(harness.controller.offset, 0);
        _expectReferenceLayout(
          harness.reference(to),
          0,
          reason: 'back at the top',
        );
      });
    }

    testWidgets('changing the crossAxisCount only builds the children around '
        'the viewport', (tester) async {
      final harness = _Harness(tester, behavior);
      addTearDown(harness.controller.dispose);
      await harness.pump(crossAxisCount: 4);
      await harness.jumpTo(30000);
      final liveChildren = builtTileRects().length;

      harness.builds = 0;
      await harness.setCrossAxisCount(3);
      // Exact mode would build the ~600 children before the viewport.
      expect(harness.builds, lessThan(liveChildren * 2));
    });

    testWidgets('approximately placed tiles come back to the same place when '
        'scrolling back and forth', (tester) async {
      final harness = _Harness(tester, behavior);
      addTearDown(harness.controller.dispose);
      await harness.pump(crossAxisCount: 4);
      await harness.jumpTo(20000);
      await harness.setCrossAxisCount(3);

      // Far enough up for the tiles around the anchor to be garbage
      // collected after the last child, then down again, then up again.
      final start = harness.controller.offset;
      final positions = <double, Map<int, Rect>>{};
      void record() {
        // Remember where tiles are for a given scroll offset.
        positions[harness.controller.offset] = builtTileRects();
      }

      for (final (delta, until) in [
        (300.0, () => harness.controller.offset < start - 4000),
        (-300.0, () => harness.controller.offset > start - 500),
        (300.0, () => harness.controller.offset < start - 4000),
      ]) {
        expect(
          await _dragCountingJumps(
            tester,
            harness.controller,
            Offset(0, delta),
            until: until,
            eachFrame: () {
              _expectNoOverlapsOrGaps(reason: 'dragging by $delta');
              record();
            },
          ),
          0,
        );
      }
      expect(tester.takeException(), isNull);

      // Every tile seen twice was at the same place relative to the content.
      final seen = <int, double>{};
      for (final MapEntry(key: offset, value: rects) in positions.entries) {
        for (final MapEntry(key: index, value: rect) in rects.entries) {
          final contentOffset = rect.top + offset;
          final previous = seen[index];
          if (previous != null) {
            expect(
              contentOffset,
              moreOrLessEquals(previous, epsilon: 1e-6),
              reason: '#$index',
            );
          }
          seen[index] = contentOffset;
        }
      }
    });

    testWidgets('jumping to the top after a change shows the exact layout', (
      tester,
    ) async {
      final harness = _Harness(tester, behavior);
      addTearDown(harness.controller.dispose);
      await harness.pump(crossAxisCount: 4);
      await harness.jumpTo(20000);
      await harness.setCrossAxisCount(3);

      await harness.jumpTo(0);
      expect(tester.takeException(), isNull);
      _expectReferenceLayout(harness.reference(3), 0, reason: 'at the top');
    });

    testWidgets('several changes in a row keep tiles stable', (tester) async {
      final harness = _Harness(tester, behavior);
      addTearDown(harness.controller.dispose);
      await harness.pump(crossAxisCount: 4);
      await harness.jumpTo(20000);

      for (final count in [3, 5, 2, 4]) {
        final (anchor, top) = _firstVisible();
        await harness.setCrossAxisCount(count);
        expect(tester.takeException(), isNull);
        _expectNoOverlapsOrGaps(reason: '$count columns');
        expect(
          tester
              .getTopLeft(find.byKey(ValueKey(anchor), skipOffstage: false))
              .dy,
          moreOrLessEquals(top, epsilon: 1e-6),
          reason: 'anchor #$anchor with $count columns',
        );
        await _dragCountingJumps(
          tester,
          harness.controller,
          const Offset(0, 300),
          until: () => harness.controller.offset < 15000,
        );
      }

      final jumps = await _dragCountingJumps(
        tester,
        harness.controller,
        const Offset(0, 300),
        eachFrame: () =>
            _expectNoOverlapsOrGaps(reason: 'while scrolling back'),
      );
      expect(jumps, lessThanOrEqualTo(1));
      _expectReferenceLayout(harness.reference(4), 0, reason: 'at the top');
    });
  });

  for (final behavior in MasonryRelayoutBehavior.values) {
    group('$behavior', () {
      testWidgets('keeps the first visible item at the same position on '
          'screen', (tester) async {
        final harness = _Harness(tester, behavior);
        addTearDown(harness.controller.dispose);
        for (final offset in [6000.0, 20000.0, 41000.0]) {
          await harness.pump(crossAxisCount: 4);
          await harness.jumpTo(offset);
          final (anchor, top) = _firstVisible();

          await harness.setCrossAxisCount(3);
          expect(
            tester
                .getTopLeft(find.byKey(ValueKey(anchor), skipOffstage: false))
                .dy,
            moreOrLessEquals(top, epsilon: 1e-6),
            reason: 'anchor #$anchor at offset $offset',
          );
        }
      });

      testWidgets('keeps the state of the visible tiles', (tester) async {
        final harness = _Harness(tester, behavior);
        addTearDown(harness.controller.dispose);
        final inits = <int, int>{};
        await harness.pump(
          crossAxisCount: 4,
          tileBuilder: (index) => _StatefulTile(
            key: ValueKey(index),
            index: index,
            onInit: (i) => inits[i] = (inits[i] ?? 0) + 1,
          ),
        );
        await harness.jumpTo(20000);
        final visibleBefore = builtTileRects().entries
            .where((e) => e.value.bottom > 0 && e.value.top < _height)
            .map((e) => e.key)
            .toSet();

        await harness.setCrossAxisCount(3);
        expect(tester.takeException(), isNull);
        for (final index in visibleBefore) {
          if (find.byKey(ValueKey(index)).evaluate().isNotEmpty) {
            expect(inits[index], 1, reason: '#$index was rebuilt from scratch');
          }
        }
      });
    });
  }

  group('window resize', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const maxCrossAxisExtent = 200.0;

    Future<ScrollController> pumpExtentGrid(
      WidgetTester tester,
      MasonryRelayoutBehavior behavior,
    ) async {
      addTearDown(() => binding.setSurfaceSize(null));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MasonryGridView.extent(
            controller: controller,
            maxCrossAxisExtent: maxCrossAxisExtent,
            mainAxisSpacing: _spacing,
            crossAxisSpacing: _spacing,
            relayoutBehavior: behavior,
            itemCount: _itemCount,
            itemBuilder: (context, index) => AspectRatio(
              key: ValueKey(index),
              aspectRatio: masonryTestRatioOf(index),
            ),
          ),
        ),
      );
      controller.jumpTo(10000);
      await tester.pump();
      return controller;
    }

    List<Offset> referenceFor(double width) => referenceMasonryLayout(
      itemCount: _itemCount,
      crossAxisCount: (width / (maxCrossAxisExtent + _spacing)).ceil(),
      crossAxisExtent: width,
      spacing: _spacing,
    );

    // 800 -> 4 columns, 500 -> 3, 900 -> 5, 400 -> 2. 700 and 810 keep 4
    // columns (any width in (612, 816]) but change their width.
    const widths = [500.0, 900.0, 700.0, 400.0, 810.0, 800.0];

    testWidgets('exact: keeps an exact layout through every resize', (
      tester,
    ) async {
      final controller = await pumpExtentGrid(
        tester,
        MasonryRelayoutBehavior.exact,
      );
      for (final width in widths) {
        await binding.setSurfaceSize(Size(width, _height));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'width $width');
        _expectReferenceLayout(
          referenceFor(width),
          controller.offset,
          reason: 'width $width',
        );
      }
    });

    for (final behavior in MasonryRelayoutBehavior.values) {
      for (final width in [700.0, 810.0]) {
        testWidgets('$behavior: resizing to $width px without changing the '
            'column count does not make visible tiles jump while scrolling '
            'back up', (tester) async {
          final controller = await pumpExtentGrid(tester, behavior);
          await binding.setSurfaceSize(Size(width, _height));
          await tester.pump();

          final jumps = await _dragCountingJumps(
            tester,
            controller,
            const Offset(0, 300),
            eachFrame: () =>
                _expectNoOverlapsOrGaps(reason: 'while scrolling back'),
          );
          expect(
            jumps,
            behavior == MasonryRelayoutBehavior.exact ? 0 : lessThan(2),
          );
          expect(tester.takeException(), isNull);
          _expectReferenceLayout(
            referenceFor(width),
            0,
            reason: 'back at the top',
          );
        });
      }
    }
  });
}
