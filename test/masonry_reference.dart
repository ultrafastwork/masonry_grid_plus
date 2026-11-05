import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Aspect ratio of the test tile at [index]. Tiles are [AspectRatio] widgets,
/// so their height depends on the column width, like image tiles in real apps.
double masonryTestRatioOf(int index) => 0.5 + ((index * 37) % 100) / 100;

/// Computes where a vertical, left-to-right masonry grid places every item
/// when laid out from the top: each item goes to the first shortest column.
///
/// The arithmetic mirrors `RenderSliverMasonryGrid` so the results can be
/// compared exactly.
List<Offset> referenceMasonryLayout({
  required int itemCount,
  required int crossAxisCount,
  required double crossAxisExtent,
  required double spacing,
  double? mainAxisSpacing,
  double Function(int index) ratioOf = masonryTestRatioOf,
}) {
  final stride = (crossAxisExtent + spacing) / crossAxisCount;
  final width = stride - spacing;
  final mainSpacing = mainAxisSpacing ?? spacing;
  final columns = List<double>.filled(crossAxisCount, 0);
  final result = <Offset>[];
  for (var i = 0; i < itemCount; i++) {
    var column = 0;
    for (var c = 1; c < crossAxisCount; c++) {
      if (columns[c] < columns[column]) {
        column = c;
      }
    }
    result.add(Offset(column * stride, columns[column]));
    columns[column] = columns[column] + width / ratioOf(i) + mainSpacing;
  }
  return result;
}

/// Returns the global rect of every built tile keyed with a `ValueKey<int>`,
/// including tiles in the cache area outside the viewport.
Map<int, Rect> builtTileRects() {
  final result = <int, Rect>{};
  for (final element
      in find.byType(AspectRatio, skipOffstage: false).evaluate()) {
    final key = element.widget.key;
    if (key is! ValueKey<int>) {
      continue;
    }
    final box = element.renderObject! as RenderBox;
    result[key.value] = box.localToGlobal(Offset.zero) & box.size;
  }
  return result;
}
