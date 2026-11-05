import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_grid_plus/masonry_grid_plus.dart';
import 'package:masonry_grid_plus/src/widgets/uniform_track.dart';

void main() {
  group('StaggeredGrid', () {
    testWidgets('fit tiles work with a reversed axis direction', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: StaggeredGrid.count(
                crossAxisCount: 2,
                axisDirection: AxisDirection.up,
                children: const [
                  StaggeredGridTile.fit(
                    crossAxisCellCount: 1,
                    child: SizedBox(key: ValueKey(0), height: 50),
                  ),
                  StaggeredGridTile.count(
                    crossAxisCellCount: 1,
                    mainAxisCellCount: 1,
                    child: SizedBox(key: ValueKey(1)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Grid main axis extent is 200 (the 1x1 tile is 200x200), so the 50px
      // fit tile is mirrored to the bottom of the grid.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(0))),
        const Offset(0, 150),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(1))),
        const Offset(200, 0),
      );
    });

    testWidgets('dry layout uses dry sizes and does not move children', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: StaggeredGrid.count(
                crossAxisCount: 2,
                children: const [
                  StaggeredGridTile.fit(
                    crossAxisCellCount: 1,
                    child: SizedBox(key: ValueKey(0), height: 50),
                  ),
                  StaggeredGridTile.fit(
                    crossAxisCellCount: 1,
                    child: SizedBox(key: ValueKey(1), height: 80),
                  ),
                  StaggeredGridTile.fit(
                    crossAxisCellCount: 2,
                    child: SizedBox(key: ValueKey(2), height: 30),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final grid = tester.renderObject<RenderBox>(find.byType(StaggeredGrid));
      final before = [
        for (var i = 0; i < 3; i++) tester.getTopLeft(find.byKey(ValueKey(i))),
      ];

      final drySize = grid.getDryLayout(const BoxConstraints(maxWidth: 400));
      expect(tester.takeException(), isNull);
      expect(drySize, grid.size);
      expect(drySize, const Size(400, 110));

      final after = [
        for (var i = 0; i < 3; i++) tester.getTopLeft(find.byKey(ValueKey(i))),
      ];
      expect(after, before);
    });
  });

  testWidgets('UniformTrack supports dry layout', (WidgetTester tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: UniformTrack(
              division: 2,
              direction: AxisDirection.right,
              children: const [SizedBox(height: 20), SizedBox(height: 40)],
            ),
          ),
        ),
      ),
    );

    final track = tester.renderObject<RenderBox>(find.byType(UniformTrack));
    final size = track.size;
    final drySize = track.getDryLayout(const BoxConstraints(maxWidth: 400));
    expect(tester.takeException(), isNull);
    expect(drySize, const Size(400, 40));
    expect(track.size, size);
  });

  group('shouldRelayout', () {
    test('quilted delegate detects pattern changes', () {
      SliverQuiltedGridDelegate create(
        List<QuiltedGridTile> pattern, {
        QuiltedGridRepeatPattern repeat = QuiltedGridRepeatPattern.same,
      }) {
        return SliverQuiltedGridDelegate(
          crossAxisCount: 4,
          pattern: pattern,
          repeatPattern: repeat,
        );
      }

      // Both patterns fill a 2x4 block.
      List<QuiltedGridTile> patternA() => const [
        QuiltedGridTile(2, 2),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 2),
      ];
      List<QuiltedGridTile> patternB() => const [
        QuiltedGridTile(2, 2),
        QuiltedGridTile(1, 2),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
      ];

      final a = create(patternA());
      expect(create(patternA()).shouldRelayout(a), isFalse);
      expect(create(patternB()).shouldRelayout(a), isTrue);
      expect(
        create(
          patternA(),
          repeat: QuiltedGridRepeatPattern.inverted,
        ).shouldRelayout(a),
        isTrue,
      );
    });

    test('pattern delegates compare patterns by value', () {
      SliverWovenGridDelegate woven(double aspectRatio) {
        return SliverWovenGridDelegate.count(
          crossAxisCount: 2,
          pattern: [WovenGridTile(aspectRatio), const WovenGridTile(1)],
        );
      }

      expect(woven(0.5).shouldRelayout(woven(0.5)), isFalse);
      expect(woven(0.5).shouldRelayout(woven(0.7)), isTrue);

      SliverStairedGridDelegate staired(double ratio) {
        return SliverStairedGridDelegate(
          pattern: [StairedGridTile(ratio, 1), const StairedGridTile(0.5, 1)],
        );
      }

      expect(staired(0.5).shouldRelayout(staired(0.5)), isFalse);
      expect(staired(0.5).shouldRelayout(staired(0.4)), isTrue);
    });
  });

  testWidgets('MasonryGridView keeps exact positions while scrolling', (
    WidgetTester tester,
  ) async {
    // Screen size is 800x600 in the test environment.
    const itemCount = 300;
    const crossAxisCount = 4;
    const spacing = 4.0;
    double heightOf(int index) => 40.0 + (index * 37) % 160;

    // Reference masonry layout: each item goes to the first shortest column.
    final columns = List<double>.filled(crossAxisCount, 0);
    final expected = <Offset>[];
    for (var i = 0; i < itemCount; i++) {
      var column = 0;
      for (var c = 1; c < crossAxisCount; c++) {
        if (columns[c] < columns[column]) {
          column = c;
        }
      }
      expected.add(
        Offset(column * (800 + spacing) / crossAxisCount, columns[column]),
      );
      columns[column] += heightOf(i) + spacing;
    }

    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MasonryGridView.count(
          controller: controller,
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          itemCount: itemCount,
          itemBuilder: (context, index) =>
              SizedBox(key: ValueKey(index), height: heightOf(index)),
        ),
      ),
    );

    void verifyVisibleChildren() {
      final scrollOffset = controller.offset;
      var checked = 0;
      for (var i = 0; i < itemCount; i++) {
        final finder = find.byKey(ValueKey(i), skipOffstage: false);
        if (finder.evaluate().isEmpty) {
          continue;
        }
        final topLeft = tester.getTopLeft(finder);
        expect(topLeft.dx, moreOrLessEquals(expected[i].dx), reason: '#$i');
        expect(
          topLeft.dy,
          moreOrLessEquals(expected[i].dy - scrollOffset),
          reason: '#$i at scroll offset $scrollOffset',
        );
        checked++;
      }
      expect(checked, greaterThan(0));
    }

    verifyVisibleChildren();
    // Jump forward and backward, which exercises both the trailing and the
    // leading child reconstruction paths.
    for (final offset in [1500.0, 6000.0, 3000.0, 9000.0, 500.0, 0.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      verifyVisibleChildren();
    }
    // Small incremental drags.
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(MasonryGridView), const Offset(0, -150));
      await tester.pump();
      verifyVisibleChildren();
    }
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(MasonryGridView), const Offset(0, 150));
      await tester.pump();
      verifyVisibleChildren();
    }
  });
}
