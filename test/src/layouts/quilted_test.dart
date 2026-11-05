import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_grid_plus/masonry_grid_plus.dart';

import '../../common.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('Patterns that do not fill complete rows', () {
    Future<void> pumpGrid(
      WidgetTester tester,
      List<QuiltedGridTile> pattern, {
      QuiltedGridRepeatPattern repeatPattern = QuiltedGridRepeatPattern.same,
    }) async {
      await binding.setSurfaceSize(const Size(800, 800));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GridView.custom(
            gridDelegate: SliverQuiltedGridDelegate(
              crossAxisCount: 4,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              repeatPattern: repeatPattern,
              pattern: pattern,
            ),
            childrenDelegate: SliverChildBuilderDelegate(
              (context, index) => Tile(index: index),
              childCount: 12,
            ),
          ),
        ),
      );
    }

    const s1 = 197.0;
    const s2 = 398.0;
    const stride = 201.0;

    testWidgets('leave gaps instead of throwing', (WidgetTester tester) async {
      await pumpGrid(tester, const [
        QuiltedGridTile(2, 2),
        QuiltedGridTile(1, 1),
      ]);
      expect(tester.takeException(), isNull);

      // A A B .
      // A A . .
      // C C D .
      // C C . .
      expect(tester.getTopLeft(find.text('0')), Offset.zero);
      expect(tester.getSize(find.text('0')), const Size(s2, s2));
      expect(tester.getTopLeft(find.text('1')), const Offset(2 * stride, 0));
      expect(tester.getSize(find.text('1')), const Size(s1, s1));
      expect(tester.getTopLeft(find.text('2')), const Offset(0, 2 * stride));
      expect(
        tester.getTopLeft(find.text('3')),
        const Offset(2 * stride, 2 * stride),
      );
    });

    testWidgets('wrap a wide tile that does not fit in the remaining columns', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, const [
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 2),
      ]);
      expect(tester.takeException(), isNull);

      // A B C .
      // D D . .
      expect(tester.getTopLeft(find.text('2')), const Offset(2 * stride, 0));
      expect(tester.getTopLeft(find.text('3')), const Offset(0, stride));
      expect(tester.getSize(find.text('3')), const Size(s2, s1));
      expect(tester.getTopLeft(find.text('4')), const Offset(0, 2 * stride));
    });

    for (final repeatPattern in [
      QuiltedGridRepeatPattern.inverted,
      QuiltedGridRepeatPattern.mirrored,
    ]) {
      testWidgets('work with $repeatPattern', (WidgetTester tester) async {
        await pumpGrid(tester, const [
          QuiltedGridTile(2, 2),
          QuiltedGridTile(1, 1),
        ], repeatPattern: repeatPattern);
        expect(tester.takeException(), isNull);

        // No two visible tiles overlap.
        final rects = [
          for (var i = 0; i < 12; i++)
            if (find.text('$i').evaluate().isNotEmpty)
              tester.getRect(find.text('$i')),
        ];
        expect(rects, isNotEmpty);
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            final overlap = rects[i].intersect(rects[j]);
            expect(
              overlap.width > 0 && overlap.height > 0,
              isFalse,
              reason: 'tiles $i and $j overlap',
            );
          }
        }
      });
    }

    testWidgets('build every visible tile when the viewport ends in a gap', (
      WidgetTester tester,
    ) async {
      // A A B .   <- row 0
      // A A . .   <- row 1, where the viewport ends: only tile 0 is in it.
      await binding.setSurfaceSize(const Size(800, 300));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GridView.custom(
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            gridDelegate: SliverQuiltedGridDelegate(
              crossAxisCount: 4,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              pattern: const [QuiltedGridTile(2, 2), QuiltedGridTile(1, 1)],
            ),
            childrenDelegate: SliverChildBuilderDelegate(
              (context, index) => Tile(index: index),
              childCount: 12,
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    test('a tile wider than the grid is reported clearly', () {
      expect(
        () => SliverQuiltedGridDelegate(
          crossAxisCount: 2,
          pattern: const [QuiltedGridTile(1, 3)],
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            contains('crossAxisCount'),
          ),
        ),
      );
    });
  });

  testWidgets('Quilted Grid same control test', (WidgetTester tester) async {
    await binding.setSurfaceSize(const Size(800, 800));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.custom(
          gridDelegate: SliverQuiltedGridDelegate(
            crossAxisCount: 4,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            repeatPattern: QuiltedGridRepeatPattern.same,
            pattern: const [
              QuiltedGridTile(2, 2),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 2),
            ],
          ),
          childrenDelegate: SliverChildBuilderDelegate(
            (context, index) => Tile(index: index),
          ),
        ),
      ),
    );

    void expectSize(int index, Size size) {
      expect(tester.getSize(find.text('$index')), equals(size));
    }

    void expectTopLeft(int index, Offset topLeft) {
      expect(tester.getTopLeft(find.text('$index')), equals(topLeft));
    }

    const s1 = 197.0;
    const s2 = 398.0;
    const s3 = 599.0;
    expectSize(0, const Size(s2, s2));
    expectSize(1, const Size(s1, s1));
    expectSize(2, const Size(s1, s1));
    expectSize(3, const Size(s2, s1));
    expectSize(4, const Size(s2, s2));
    expectSize(5, const Size(s1, s1));
    expectSize(6, const Size(s1, s1));
    expectSize(7, const Size(s2, s1));

    expectTopLeft(0, const Offset(0, 0));
    expectTopLeft(1, const Offset(s2 + 4, 0));
    expectTopLeft(2, const Offset(s3 + 4, 0));
    expectTopLeft(3, const Offset(s2 + 4, s1 + 4));
    expectTopLeft(4, const Offset(0, s2 + 4));
    expectTopLeft(5, const Offset(s2 + 4, s2 + 4));
    expectTopLeft(6, const Offset(s3 + 4, s2 + 4));
    expectTopLeft(7, const Offset(s2 + 4, s3 + 4));
  });

  testWidgets('Quilted Grid inverted control test', (
    WidgetTester tester,
  ) async {
    await binding.setSurfaceSize(const Size(800, 800));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.custom(
          gridDelegate: SliverQuiltedGridDelegate(
            crossAxisCount: 4,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            repeatPattern: QuiltedGridRepeatPattern.inverted,
            pattern: const [
              QuiltedGridTile(2, 2),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 2),
            ],
          ),
          childrenDelegate: SliverChildBuilderDelegate(
            (context, index) => Tile(index: index),
          ),
        ),
      ),
    );

    void expectSize(int index, Size size) {
      expect(tester.getSize(find.text('$index')), equals(size));
    }

    void expectTopLeft(int index, Offset topLeft) {
      expect(tester.getTopLeft(find.text('$index')), equals(topLeft));
    }

    const s1 = 197.0;
    const s2 = 398.0;
    const s3 = 599.0;
    expectSize(0, const Size(s2, s2));
    expectSize(1, const Size(s1, s1));
    expectSize(2, const Size(s1, s1));
    expectSize(3, const Size(s2, s1));
    expectSize(4, const Size(s2, s1));
    expectSize(5, const Size(s2, s2));
    expectSize(6, const Size(s1, s1));
    expectSize(7, const Size(s1, s1));

    expectTopLeft(0, const Offset(0, 0));
    expectTopLeft(1, const Offset(s2 + 4, 0));
    expectTopLeft(2, const Offset(s3 + 4, 0));
    expectTopLeft(3, const Offset(s2 + 4, s1 + 4));
    expectTopLeft(4, const Offset(0, s2 + 4));
    expectTopLeft(5, const Offset(s2 + 4, s2 + 4));
    expectTopLeft(6, const Offset(0, s3 + 4));
    expectTopLeft(7, const Offset(s1 + 4, s3 + 4));
  });

  testWidgets('Quilted Grid mirrored control test', (
    WidgetTester tester,
  ) async {
    await binding.setSurfaceSize(const Size(800, 800));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.custom(
          gridDelegate: SliverQuiltedGridDelegate(
            crossAxisCount: 4,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            repeatPattern: QuiltedGridRepeatPattern.mirrored,
            pattern: const [
              QuiltedGridTile(2, 2),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 2),
            ],
          ),
          childrenDelegate: SliverChildBuilderDelegate(
            (context, index) => Tile(index: index),
          ),
        ),
      ),
    );

    void expectSize(int index, Size size) {
      expect(tester.getSize(find.text('$index')), equals(size));
    }

    void expectTopLeft(int index, Offset topLeft) {
      expect(tester.getTopLeft(find.text('$index')), equals(topLeft));
    }

    const s1 = 197.0;
    const s2 = 398.0;
    const s3 = 599.0;
    expectSize(0, const Size(s2, s2));
    expectSize(1, const Size(s1, s1));
    expectSize(2, const Size(s1, s1));
    expectSize(3, const Size(s2, s1));
    expectSize(4, const Size(s2, s2));
    expectSize(5, const Size(s2, s1));
    expectSize(6, const Size(s1, s1));
    expectSize(7, const Size(s1, s1));

    expectTopLeft(0, const Offset(0, 0));
    expectTopLeft(1, const Offset(s2 + 4, 0));
    expectTopLeft(2, const Offset(s3 + 4, 0));
    expectTopLeft(3, const Offset(s2 + 4, s1 + 4));
    expectTopLeft(4, const Offset(0, s2 + 4));
    expectTopLeft(5, const Offset(s2 + 4, s2 + 4));
    expectTopLeft(6, const Offset(s2 + 4, s3 + 4));
    expectTopLeft(7, const Offset(s3 + 4, s3 + 4));
  });

  testWidgets('Quilted Grid different pattern control test', (
    WidgetTester tester,
  ) async {
    await binding.setSurfaceSize(const Size(200, 268));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.custom(
          gridDelegate: SliverQuiltedGridDelegate(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            repeatPattern: QuiltedGridRepeatPattern.inverted,
            pattern: const [
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(2, 2),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
              QuiltedGridTile(1, 1),
            ],
          ),
          childrenDelegate: SliverChildBuilderDelegate(
            (context, index) => Tile(index: index),
          ),
        ),
      ),
    );

    void expectSize(int index, Size size) {
      expect(tester.getSize(find.text('$index')), equals(size));
    }

    void expectTopLeft(int index, Offset topLeft) {
      expect(tester.getTopLeft(find.text('$index')), equals(topLeft));
    }

    const s1 = 64.0;
    const s2 = 132.0;
    const s3 = 200.0;
    expectSize(0, const Size(s1, s1));
    expectSize(1, const Size(s1, s1));
    expectSize(2, const Size(s1, s1));
    expectSize(3, const Size(s1, s1));
    expectSize(4, const Size(s2, s2));
    expectSize(5, const Size(s1, s1));
    expectSize(6, const Size(s1, s1));
    expectSize(7, const Size(s1, s1));
    expectSize(7, const Size(s1, s1));

    expectTopLeft(0, const Offset(0, 0));
    expectTopLeft(1, const Offset(s1 + 4, 0));
    expectTopLeft(2, const Offset(s2 + 4, 0));
    expectTopLeft(3, const Offset(0, s1 + 4));
    expectTopLeft(4, const Offset(s1 + 4, s1 + 4));
    expectTopLeft(5, const Offset(0, s2 + 4));
    expectTopLeft(6, const Offset(0, s3 + 4));
    expectTopLeft(7, const Offset(s1 + 4, s3 + 4));
    expectTopLeft(8, const Offset(s2 + 4, s3 + 4));
  });

  test('computeMaxScrollOffset should be right', () {
    final delegate = SliverQuiltedGridDelegate(
      crossAxisCount: 4,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      repeatPattern: QuiltedGridRepeatPattern.same,
      pattern: const [
        QuiltedGridTile(2, 2),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 2),
      ],
    );

    final layout = delegate.getLayout(
      const SliverConstraints(
        axisDirection: AxisDirection.down,
        cacheOrigin: 0,
        crossAxisDirection: AxisDirection.right,
        crossAxisExtent: 412,
        growthDirection: GrowthDirection.forward,
        scrollOffset: 0,
        overlap: 0,
        viewportMainAxisExtent: 400,
        precedingScrollExtent: 0,
        remainingCacheExtent: 400,
        remainingPaintExtent: 400,
        userScrollDirection: ScrollDirection.idle,
      ),
    );

    expect(layout.computeMaxScrollOffset(12), 620);
    expect(layout.computeMaxScrollOffset(16), 828);
  });
}
