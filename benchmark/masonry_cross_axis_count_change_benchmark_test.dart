// Measures the cost of a MasonryGridView column count change at various
// scroll depths.
//
// Run with:
//   flutter test benchmark/masonry_cross_axis_count_change_benchmark_test.dart
//
// It lives outside test/ so it is not part of the regular suite. `flutter
// test` runs in a debug-mode VM, so absolute times are much higher than in a
// profile/release build on a device. The build counts are exact, and the
// ratio between the change frame and a normal scroll frame is the useful
// signal.

// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_grid_plus/masonry_grid_plus.dart';

import '../test/masonry_reference.dart';

const _itemCount = 20000;
const _spacing = 4.0;
const _depths = [100, 500, 2000, 5000, 10000];

/// A tile closer to a real card than a bare box: decoration, padding, two
/// lines of text.
Widget _cardTile(BuildContext context, int index) {
  return AspectRatio(
    key: ValueKey(index),
    aspectRatio: masonryTestRatioOf(index),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.primaries[index % Colors.primaries.length],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: Text('Item $index', maxLines: 1)),
            Flexible(child: Text('Subtitle for $index', maxLines: 2)),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('MasonryGridView crossAxisCount change cost', (tester) async {
    final rows = <String>[];
    final reference = referenceMasonryLayout(
      itemCount: _itemCount,
      crossAxisCount: 4,
      crossAxisExtent: 800,
      spacing: _spacing,
    );

    for (final (behavior, depth) in [
      for (final behavior in MasonryRelayoutBehavior.values)
        for (final depth in _depths) (behavior, depth),
    ]) {
      final controller = ScrollController();
      var crossAxisCount = 4;
      var builds = 0;
      late StateSetter setState;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, s) {
              setState = s;
              return MasonryGridView.count(
                controller: controller,
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: _spacing,
                crossAxisSpacing: _spacing,
                relayoutBehavior: behavior,
                itemCount: _itemCount,
                itemBuilder: (context, index) {
                  builds++;
                  return _cardTile(context, index);
                },
              );
            },
          ),
        ),
      );
      controller.jumpTo(reference[depth].dy);
      await tester.pump();

      // Normal scroll frame, for comparison. Warm up once first.
      controller.jumpTo(controller.offset + 50);
      await tester.pump();
      builds = 0;
      final scrollWatch = Stopwatch()..start();
      controller.jumpTo(controller.offset + 50);
      await tester.pump();
      scrollWatch.stop();
      final scrollBuilds = builds;

      builds = 0;
      final changeWatch = Stopwatch()..start();
      setState(() => crossAxisCount = 3);
      await tester.pump();
      changeWatch.stop();
      final changeBuilds = builds;

      final scrollMs = scrollWatch.elapsedMicroseconds / 1000;
      final changeMs = changeWatch.elapsedMicroseconds / 1000;
      rows.add(
        '${behavior.name.padRight(8)} | '
        '${'$depth'.padLeft(6)} | '
        '${'$changeBuilds'.padLeft(13)} | '
        '${changeMs.toStringAsFixed(1).padLeft(14)} | '
        '${'$scrollBuilds'.padLeft(12)} | '
        '${scrollMs.toStringAsFixed(1).padLeft(13)} | '
        '${(changeMs / scrollMs).toStringAsFixed(0).padLeft(5)}x',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }

    print('');
    print(
      'behavior |  depth | change builds | change ms (dbg) | scroll builds | scroll ms (dbg) | ratio',
    );
    print(
      '---------|--------|---------------|-----------------|---------------|-----------------|------',
    );
    rows.forEach(print);
  });
}
