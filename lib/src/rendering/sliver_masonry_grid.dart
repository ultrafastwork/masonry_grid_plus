import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:masonry_grid_plus/src/foundation/extensions.dart';
import 'package:masonry_grid_plus/src/rendering/sliver_simple_grid_delegate.dart';

/// How a masonry grid repositions its children when its column layout (the
/// number of columns, their width, or the spacing between children) changes
/// while it is scrolled away from its start.
///
/// This happens, for example, when the device rotates, when an app enters
/// split-screen, or when a window is resized.
enum MasonryRelayoutBehavior {
  /// Lays out every child before the first visible one again, so the result
  /// is identical to a grid built from scratch at the new size.
  ///
  /// The first visible child keeps its position on screen. The cost of the
  /// change grows with the index of that child: every child before it is
  /// built and laid out once, in a single frame.
  exact,

  /// Keeps the first visible child at its position on screen and lays out the
  /// grid from there, without visiting the children before it.
  ///
  /// The cost of the change only depends on the children around the
  /// viewport. Children before the first visible one are placed
  /// approximately as they scroll into view: they never overlap, and tiles on
  /// screen do not move while scrolling, but the arrangement can differ from
  /// a grid built from scratch. Once the start of the grid is reached, the
  /// grid switches back to the exact arrangement, which moves the tiles on
  /// screen once.
  anchored,
}

/// Parent data structure used by [RenderSliverMasonryGrid].
class SliverMasonryGridParentData extends SliverMultiBoxAdaptorParentData {
  /// The index of the child in the non-scrolling axis.
  int? crossAxisIndex;

  /// The last extent for this child before it was garbage.
  /// This is used to retrieve the last offset of this child and prevent
  /// mis-placing issues.
  double? lastMainAxisExtent;

  @override
  String toString() => 'crossAxisIndex=$crossAxisIndex; ${super.toString()}';
}

/// A sliver that places multiple box children in a two dimensional arrangement.
///
/// [RenderSliverMasonryGrid] places each child the nearest as possible at the
/// start of the main axis and then at the start of the cross axis.
/// For example, in a vertical list, with left-to-right text direction, a child
/// will be placed as close as possible at the top of the grid, and then as
/// close as possible to the left side of the grid.
///
/// The [gridDelegate] determines how many children can be placed in the cross
/// axis.
class RenderSliverMasonryGrid extends RenderSliverMultiBoxAdaptor {
  /// Creates a sliver that places its children in a Masonry layout.
  ///
  /// The [mainAxisSpacing] and [crossAxisSpacing] arguments must be greater
  /// than zero.
  RenderSliverMasonryGrid({
    required super.childManager,
    required SliverSimpleGridDelegate gridDelegate,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    this.relayoutBehavior = MasonryRelayoutBehavior.exact,
  }) : assert(mainAxisSpacing >= 0),
       assert(crossAxisSpacing >= 0),
       _gridDelegate = gridDelegate,
       _mainAxisSpacing = mainAxisSpacing,
       _crossAxisSpacing = crossAxisSpacing;

  /// {@template fsgv.global.gridDelegate}
  /// The delegate that controls the size and position of the children.
  /// {@endtemplate}
  SliverSimpleGridDelegate get gridDelegate => _gridDelegate;
  SliverSimpleGridDelegate _gridDelegate;
  set gridDelegate(SliverSimpleGridDelegate value) {
    if (_gridDelegate == value) {
      return;
    }

    if (value.runtimeType != _gridDelegate.runtimeType ||
        value.shouldRelayout(_gridDelegate)) {
      markNeedsLayout();
    }

    _gridDelegate = value;
  }

  /// {@template fsgv.global.mainAxisSpacing}
  /// The number of pixels between each child along the main axis.
  /// {@endtemplate}
  double get mainAxisSpacing => _mainAxisSpacing;
  double _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    if (_mainAxisSpacing == value) {
      return;
    }
    _mainAxisSpacing = value;
    markNeedsLayout();
  }

  /// {@template fsgv.global.crossAxisSpacing}
  /// The number of pixels between each child along the cross axis.
  /// {@endtemplate}
  double get crossAxisSpacing => _crossAxisSpacing;
  double _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    if (_crossAxisSpacing == value) {
      return;
    }
    _crossAxisSpacing = value;
    markNeedsLayout();
  }

  /// {@template fsgv.global.relayoutBehavior}
  /// How the children are repositioned when the column layout changes while
  /// the grid is scrolled away from its start.
  ///
  /// Defaults to [MasonryRelayoutBehavior.exact].
  /// {@endtemplate}
  ///
  /// Changing it does not trigger a layout: it is only used when the column
  /// layout changes, which triggers a layout on its own.
  MasonryRelayoutBehavior relayoutBehavior;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverMasonryGridParentData) {
      child.parentData = SliverMasonryGridParentData();
    }
  }

  SliverMasonryGridParentData _getParentData(RenderObject child) {
    return child.parentData as SliverMasonryGridParentData;
  }

  double _stride = 0;
  int _crossAxisCount = 1;
  bool _reverseCrossAxis = false;

  @override
  double childCrossAxisPosition(RenderBox child) {
    final crossAxisIndex = _childCrossAxisIndex(child)!;
    final effectiveIndex = _reverseCrossAxis
        ? _crossAxisCount - crossAxisIndex - 1
        : crossAxisIndex;
    return effectiveIndex * _stride;
  }

  int? _childCrossAxisIndex(RenderBox child) {
    return _getParentData(child).crossAxisIndex;
  }

  /// Contains the cross axis indexes of all children before the current
  /// firstChild.
  final _previousCrossAxisIndexes = <int>[];

  /// Contains the main axis extents of all children before the current
  /// firstChild.
  /// We have to keep track of these because the size may have changed since,
  /// and we don't want to screw up the layout.
  final _previousMainAxisExtents = <double>[];

  /// The index of the child kept in place by the last
  /// [MasonryRelayoutBehavior.anchored] relayout, or null when the whole grid
  /// is laid out exactly.
  ///
  /// Children after it are laid out as usual, starting from
  /// [_anchorFrontier]. Children before it have approximate positions: each
  /// keeps its column, and is stacked below the previous child of that column.
  int? _anchorIndex;

  /// The main axis offset at which each column starts right before the child
  /// at [_anchorIndex].
  Float64List? _anchorFrontier;

  /// The columns of children before [_anchorIndex] that were garbage collected
  /// after the last child, so they come back to the same column. The last
  /// entries are for the lowest indexes.
  final _nextChildIndexes = <int>[];
  final _nextCrossAxisIndexes = <int>[];

  void _clearAnchor() {
    _anchorIndex = null;
    _anchorFrontier = null;
    _nextChildIndexes.clear();
    _nextCrossAxisIndexes.clear();
  }

  bool _isApproximate(RenderBox child) {
    final anchorIndex = _anchorIndex;
    return anchorIndex != null && indexOf(child) < anchorIndex;
  }

  @override
  bool addInitialChild({int index = 0, double layoutOffset = 0.0}) {
    final hasFirstChild = super.addInitialChild(
      index: index,
      layoutOffset: layoutOffset,
    );
    if (hasFirstChild) {
      final parentData = _getParentData(firstChild!);
      parentData.applyZero();
    }
    return hasFirstChild;
  }

  @override
  void collectGarbage(int leadingGarbage, int trailingGarbage) {
    int count = leadingGarbage;
    RenderBox? child = firstChild;
    while (count > 0 && child != null) {
      final crossAxisIndex = _childCrossAxisIndex(child);
      if (crossAxisIndex != null) {
        _previousCrossAxisIndexes.add(crossAxisIndex);
        _previousMainAxisExtents.add(paintExtentOf(child));
      }
      child = childAfter(child);
      count -= 1;
    }

    // Approximately placed children are not re-flowed, so remember their
    // column in case they come back after the last child.
    if (_anchorIndex != null) {
      count = trailingGarbage;
      child = lastChild;
      while (count > 0 && child != null) {
        final crossAxisIndex = _childCrossAxisIndex(child);
        if (_isApproximate(child) && crossAxisIndex != null) {
          _nextChildIndexes.add(indexOf(child));
          _nextCrossAxisIndexes.add(crossAxisIndex);
        }
        child = childBefore(child);
        count -= 1;
      }
    }
    super.collectGarbage(leadingGarbage, trailingGarbage);
  }

  @override
  RenderBox? insertAndLayoutLeadingChild(
    BoxConstraints childConstraints, {
    bool parentUsesSize = false,
  }) {
    final child = super.insertAndLayoutLeadingChild(
      childConstraints,
      parentUsesSize: parentUsesSize,
    );
    if (child != null) {
      final parentData = _getParentData(child);
      if (_previousCrossAxisIndexes.isNotEmpty) {
        parentData.crossAxisIndex = _previousCrossAxisIndexes.removeLast();
        parentData.lastMainAxisExtent = _previousMainAxisExtents.removeLast();
      } else if (_anchorIndex != null) {
        // Never laid out at the current size: the position is chosen when
        // the child is placed.
        parentData.crossAxisIndex = null;
        parentData.lastMainAxisExtent = null;
      } else {
        parentData.crossAxisIndex = 0;
        parentData.lastMainAxisExtent = 0;
      }
    }

    return child;
  }

  @override
  RenderBox? insertAndLayoutChild(
    BoxConstraints childConstraints, {
    required RenderBox? after,
    bool parentUsesSize = false,
  }) {
    final child = super.insertAndLayoutChild(
      childConstraints,
      after: after,
      parentUsesSize: parentUsesSize,
    );
    if (child != null && _isApproximate(child)) {
      final index = indexOf(child);
      int? crossAxisIndex;
      if (_nextChildIndexes.isNotEmpty && _nextChildIndexes.last == index) {
        _nextChildIndexes.removeLast();
        crossAxisIndex = _nextCrossAxisIndexes.removeLast();
      } else {
        _nextChildIndexes.clear();
        _nextCrossAxisIndexes.clear();
      }
      _getParentData(child).crossAxisIndex = crossAxisIndex;
    }
    return child;
  }

  int? _lastCrossAxisCount;
  double? _lastChildCrossAxisExtent;
  double? _lastMainAxisSpacing;

  /// Returns the first child inside the viewport, according to the positions
  /// of the last layout.
  RenderBox? _firstVisibleChild() {
    final viewportStart = constraints.scrollOffset;
    final viewportEnd = viewportStart + constraints.remainingPaintExtent;
    RenderBox? child = firstChild;
    while (child != null) {
      final offset = childScrollOffset(child);
      if (offset != null &&
          child.hasSize &&
          offset < viewportEnd &&
          offset + paintExtentOf(child) > viewportStart) {
        return child;
      }
      child = childAfter(child);
    }
    return null;
  }

  /// Whether the children have consecutive indexes and have all been laid out
  /// and positioned before.
  bool _childrenAreContiguousAndPositioned() {
    RenderBox? child = firstChild;
    int? expectedIndex;
    while (child != null) {
      final index = indexOf(child);
      if ((expectedIndex != null && index != expectedIndex) ||
          childScrollOffset(child) == null ||
          _childCrossAxisIndex(child) == null ||
          !child.hasSize) {
        return false;
      }
      expectedIndex = index + 1;
      child = childAfter(child);
    }
    return true;
  }

  /// Places [child] at the start of the shortest column of [offsets], and
  /// updates [offsets].
  void _placeInShortestColumn(RenderBox child, Float64List offsets) {
    final crossAxisIndex = offsets.findSmallestIndexWithMinimumValue();
    final childParentData = _getParentData(child);
    childParentData.layoutOffset = offsets[crossAxisIndex];
    childParentData.crossAxisIndex = crossAxisIndex;
    offsets[crossAxisIndex] =
        childScrollOffset(child)! + paintExtentOf(child) + mainAxisSpacing;
  }

  /// Requests a scroll offset correction of [correction], unless it is
  /// negligible. Returns whether the correction was requested, in which case
  /// the layout must stop.
  bool _correctScrollOffset(double correction) {
    // Never scroll before the start of the sliver.
    final effectiveCorrection = correction < -constraints.scrollOffset
        ? -constraints.scrollOffset
        : correction;
    if (effectiveCorrection.abs() < precisionErrorTolerance) {
      return false;
    }
    geometry = SliverGeometry(scrollOffsetCorrection: effectiveCorrection);
    return true;
  }

  /// Moves every child by [delta] in the main axis, and scrolls by the same
  /// amount so that nothing moves on screen.
  void _shiftChildren(double delta) {
    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = _getParentData(child);
      final offset = childParentData.layoutOffset;
      if (offset != null) {
        childParentData.layoutOffset = offset + delta;
      }
      child = childAfter(child);
    }
    final anchorFrontier = _anchorFrontier;
    if (anchorFrontier != null) {
      for (int i = 0; i < anchorFrontier.length; i++) {
        anchorFrontier[i] += delta;
      }
    }
    geometry = SliverGeometry(scrollOffsetCorrection: delta);
  }

  /// Lays out every child from index 0 to the first visible one at the new
  /// column layout, and scrolls so that the first visible child stays at the
  /// same position on screen.
  ///
  /// Returns whether a scroll offset correction was requested, in which case
  /// the layout must stop.
  bool _relayoutExactly(BoxConstraints childConstraints, int crossAxisCount) {
    _previousCrossAxisIndexes.clear();
    _previousMainAxisExtents.clear();
    _clearAnchor();

    final anchor = _firstVisibleChild() ?? firstChild!;
    final anchorIndex = indexOf(anchor);
    final anchorOffset = childScrollOffset(anchor);
    final anchorScreenOffset = anchorOffset == null
        ? 0.0
        : anchorOffset - constraints.scrollOffset;

    if (!_childrenAreContiguousAndPositioned()) {
      // The children were reordered or replaced at the same time. Start over.
      collectGarbage(0, childCount);
      if (!addInitialChild()) {
        return false;
      }
    }

    // Add the children before the current first child. The children already
    // there are kept, so their state survives the change.
    while (indexOf(firstChild!) > 0) {
      if (insertAndLayoutLeadingChild(childConstraints, parentUsesSize: true) ==
          null) {
        break;
      }
    }

    final offsets = Float64List(crossAxisCount);
    RenderBox child = firstChild!;
    double? newAnchorOffset;
    while (true) {
      child.layout(childConstraints, parentUsesSize: true);
      _placeInShortestColumn(child, offsets);
      final index = indexOf(child);
      if (index == anchorIndex) {
        newAnchorOffset = childScrollOffset(child);
      }
      final next = childAfter(child);
      if (next != null) {
        child = next;
        continue;
      }
      if (index >= anchorIndex) {
        break;
      }
      final inserted = insertAndLayoutChild(
        childConstraints,
        after: child,
        parentUsesSize: true,
      );
      if (inserted == null) {
        break;
      }
      child = inserted;
    }

    if (newAnchorOffset == null) {
      return false;
    }
    return _correctScrollOffset(
      newAnchorOffset - anchorScreenOffset - constraints.scrollOffset,
    );
  }

  /// Keeps the first visible child where it is, lays out the following
  /// children from there, and places the previous ones approximately.
  ///
  /// Returns whether a scroll offset correction was requested, in which case
  /// the layout must stop.
  bool _relayoutAroundFirstVisibleChild(
    BoxConstraints childConstraints,
    int crossAxisCount,
  ) {
    final anchor = _firstVisibleChild();
    if (anchor == null ||
        indexOf(firstChild!) == 0 ||
        !_childrenAreContiguousAndPositioned()) {
      // Cheap when the first child is at index 0. Otherwise the children
      // were reordered or replaced at the same time, and the exact layout is
      // the only reliable one.
      return _relayoutExactly(childConstraints, crossAxisCount);
    }

    _previousCrossAxisIndexes.clear();
    _previousMainAxisExtents.clear();
    _clearAnchor();

    final anchorOffset = childScrollOffset(anchor)!;
    RenderBox? child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      child = childAfter(child);
    }

    final frontier = Float64List(crossAxisCount)
      ..fillRange(0, crossAxisCount, anchorOffset);
    child = anchor;
    while (child != null) {
      _placeInShortestColumn(child, frontier);
      child = childAfter(child);
    }

    // Stack the previous children upwards, filling the column that starts
    // the furthest down first.
    final columnStarts = Float64List(crossAxisCount)
      ..fillRange(0, crossAxisCount, anchorOffset);
    double minOffset = anchorOffset;
    child = childBefore(anchor);
    while (child != null) {
      final crossAxisIndex = _indexOfMaxFinite(columnStarts);
      final offset =
          columnStarts[crossAxisIndex] - paintExtentOf(child) - mainAxisSpacing;
      _getParentData(child)
        ..layoutOffset = offset
        ..crossAxisIndex = crossAxisIndex;
      columnStarts[crossAxisIndex] = offset;
      if (offset < minOffset) {
        minOffset = offset;
      }
      child = childBefore(child);
    }

    _anchorIndex = indexOf(anchor);
    _anchorFrontier = Float64List(crossAxisCount)
      ..fillRange(0, crossAxisCount, anchorOffset);

    if (minOffset < -precisionErrorTolerance) {
      _shiftChildren(-minOffset);
      return true;
    }
    return false;
  }

  /// Called once the child at index 0 is the first child while some children
  /// are approximately placed: lays out the current children exactly, and
  /// scrolls so that the first visible child stays at the same position on
  /// screen.
  ///
  /// Returns whether a scroll offset correction was requested, in which case
  /// the layout must stop.
  bool _settleApproximateLayout(
    BoxConstraints childConstraints,
    int crossAxisCount,
  ) {
    assert(indexOf(firstChild!) == 0);
    final anchor = _firstVisibleChild();
    final anchorOffset = anchor == null ? null : childScrollOffset(anchor);
    _previousCrossAxisIndexes.clear();
    _previousMainAxisExtents.clear();
    _clearAnchor();

    final offsets = Float64List(crossAxisCount);
    RenderBox? child = firstChild;
    int expectedIndex = 0;
    while (child != null) {
      if (indexOf(child) != expectedIndex) {
        // Drop the children after a gap; they will be recreated if needed.
        int remaining = 0;
        for (RenderBox? c = child; c != null; c = childAfter(c)) {
          remaining++;
        }
        collectGarbage(0, remaining);
        break;
      }
      child.layout(childConstraints, parentUsesSize: true);
      _placeInShortestColumn(child, offsets);
      expectedIndex++;
      child = childAfter(child);
    }

    if (anchor == null || anchorOffset == null || anchor.parent != this) {
      return false;
    }
    return _correctScrollOffset(childScrollOffset(anchor)! - anchorOffset);
  }

  @override
  void performLayout() {
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final crossAxisCount = _gridDelegate.getCrossAxisCount(
      constraints,
      crossAxisSpacing,
    );

    _crossAxisCount = crossAxisCount;
    _reverseCrossAxis = axisDirectionIsReversed(constraints.crossAxisDirection);

    // The stride is the cross extent of a cell + crossAxisSpacing.
    _stride = (constraints.crossAxisExtent + crossAxisSpacing) / crossAxisCount;
    final childCrossAxisExtent = _stride - crossAxisSpacing;
    final childConstraints = constraints.asBoxConstraints(
      crossAxisExtent: childCrossAxisExtent,
    );

    final double scrollOffset =
        constraints.scrollOffset + constraints.cacheOrigin;

    assert(scrollOffset >= 0.0);
    final double remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);
    final double targetEndScrollOffset = scrollOffset + remainingExtent;
    int leadingGarbage = 0;
    int trailingGarbage = 0;
    bool reachedEnd = false;

    final scrollOffsets = Float64List(crossAxisCount);

    // If the column layout changed, the positions and extents recorded for
    // the children before firstChild are no longer valid.
    final columnLayoutChanged =
        _lastCrossAxisCount != null &&
        (_lastCrossAxisCount != crossAxisCount ||
            _lastChildCrossAxisExtent != childCrossAxisExtent ||
            _lastMainAxisSpacing != mainAxisSpacing);
    _lastCrossAxisCount = crossAxisCount;
    _lastChildCrossAxisExtent = childCrossAxisExtent;
    _lastMainAxisSpacing = mainAxisSpacing;

    if (columnLayoutChanged && firstChild != null) {
      final corrected = switch (relayoutBehavior) {
        MasonryRelayoutBehavior.exact => _relayoutExactly(
          childConstraints,
          crossAxisCount,
        ),
        MasonryRelayoutBehavior.anchored => _relayoutAroundFirstVisibleChild(
          childConstraints,
          crossAxisCount,
        ),
      };
      if (corrected) {
        return;
      }
    }

    void positionChild(RenderBox child) {
      final childParentData = _getParentData(child);
      final anchorIndex = _anchorIndex;
      if (anchorIndex != null) {
        final index = indexOf(child);
        if (index < anchorIndex) {
          // Approximate positions: keep the column, and stack the child
          // below the previous child of that column.
          var crossAxisIndex = childParentData.crossAxisIndex;
          if (crossAxisIndex == null || crossAxisIndex >= crossAxisCount) {
            crossAxisIndex = scrollOffsets.findSmallestIndexWithMinimumValue();
          }
          childParentData.layoutOffset = scrollOffsets[crossAxisIndex];
          childParentData.crossAxisIndex = crossAxisIndex;
          scrollOffsets[crossAxisIndex] =
              childScrollOffset(child)! +
              paintExtentOf(child) +
              mainAxisSpacing;
          return;
        }
        final anchorFrontier = _anchorFrontier;
        if (index == anchorIndex && anchorFrontier != null) {
          // Stacking the previous children up and then down again can leave
          // precision errors, which would change which column is the
          // shortest. Snap them to the recorded frontier.
          for (int i = 0; i < crossAxisCount; i++) {
            if ((scrollOffsets[i] - anchorFrontier[i]).abs() <
                precisionErrorTolerance) {
              scrollOffsets[i] = anchorFrontier[i];
            }
          }
          anchorFrontier.setAll(0, scrollOffsets);
        }
      }
      _placeInShortestColumn(child, scrollOffsets);
    }

    // This algorithm is a more generic one that the one used by the SliverList.

    // Make sure we have at least one child to start from.
    if (firstChild == null) {
      if (!addInitialChild()) {
        // There are no children.
        geometry = SliverGeometry.zero;
        childManager.didFinishLayout();
        return;
      }
    }

    // We have at least one child.

    // These variables track the range of children that we have laid out. Within
    // this range, the children have consecutive indices. Outside this range,
    // it's possible for a child to get removed without notice.
    RenderBox? leadingChildWithLayout, trailingChildWithLayout;

    RenderBox? earliestUsefulChild = firstChild;

    // A firstChild with null layout offset is likely a result of children
    // reordering.
    //
    // We rely on firstChild to have accurate layout offset. In the case of null
    // layout offset, we have to find the first child that has valid layout
    // offset.
    if (childScrollOffset(firstChild!) == null) {
      int leadingChildrenWithoutLayoutOffset = 0;
      while (earliestUsefulChild != null &&
          childScrollOffset(earliestUsefulChild) == null) {
        earliestUsefulChild = childAfter(earliestUsefulChild);
        leadingChildrenWithoutLayoutOffset += 1;
      }
      // We should be able to destroy children with null layout offset safely,
      // because they are likely outside of viewport
      collectGarbage(leadingChildrenWithoutLayoutOffset, 0);
      // If can not find a valid layout offset, start from the initial child.
      if (firstChild == null) {
        if (!addInitialChild()) {
          // There are no children.
          geometry = SliverGeometry.zero;
          childManager.didFinishLayout();
          return;
        }
      }
    }

    // We need to compute the scroll offset of the earliest chidren.
    // Each scroll offset should be less or equals to the scrollOffset.
    // For the moment the scroll offsets represents the target scroll offset of
    // the child before the firstChild.
    scrollOffsets.fillRange(0, crossAxisCount, double.infinity);

    // Computes the SliverMasonryGridParentData for the firstChild.
    SliverMasonryGridParentData computeFirstChildParentData() {
      final child = firstChild!;
      final firstChildParentData = _getParentData(child);
      if (_isApproximate(child)) {
        // Stack the child right above the earliest child of its column, using
        // its current extent so that nothing below it moves.
        var crossAxisIndex = firstChildParentData.crossAxisIndex;
        if (crossAxisIndex == null ||
            crossAxisIndex >= crossAxisCount ||
            !scrollOffsets[crossAxisIndex].isFinite) {
          crossAxisIndex = _indexOfMaxFinite(scrollOffsets);
        }
        return SliverMasonryGridParentData()
          ..layoutOffset =
              scrollOffsets[crossAxisIndex] -
              paintExtentOf(child) -
              mainAxisSpacing
          ..crossAxisIndex = crossAxisIndex;
      }

      // We already laid out this child once before, so we must have retain it
      // last extent and crossAxisIndex.
      final mainAxisExtent =
          firstChildParentData.lastMainAxisExtent! + mainAxisSpacing;
      final crossAxisIndex = firstChildParentData.crossAxisIndex!;

      double offset = scrollOffsets[crossAxisIndex] - mainAxisExtent;

      // It's possible that we have offset is very close of other offsets, but
      // not exactly the same, due to precision errors. To avoid mis-placement,
      // we check if the offset is close to other offsets. If it's the case, we
      // change the offset with the other one.
      for (int i = 0; i < crossAxisCount; i++) {
        if (i == crossAxisIndex) {
          continue;
        }
        final otherOffset = scrollOffsets[i];
        if ((offset - otherOffset).abs() < precisionErrorTolerance) {
          offset = otherOffset;
          break;
        }
      }

      return SliverMasonryGridParentData()
        ..layoutOffset = offset
        ..crossAxisIndex = crossAxisIndex;
    }

    RenderBox? child = firstChild;

    // If a new child is inserted and does not have a valid crossAxisIndex, we
    // have to set it.
    if (child != null && indexOf(child) == 0) {
      final firstChildParentData = _getParentData(child);
      firstChildParentData.crossAxisIndex = 0;
    }

    // We populate our earliestScrollOffsets list.
    while (child != null && _anyInfinite(scrollOffsets)) {
      final index = _childCrossAxisIndex(child);
      if (index != null && index < crossAxisCount) {
        final scrollOffset = childScrollOffset(child)!;
        // We only need to set the scroll offsets of the earliest children.
        if (scrollOffsets[index] == double.infinity) {
          scrollOffsets[index] = scrollOffset;
        }
      }
      child = childAfter(child);
    }

    // Once the first child is at index 0, the approximately placed children
    // are replaced by the exact layout.
    // Returns whether the layout must stop.
    bool settled = false;
    bool settleIfAtStart() {
      if (_anchorIndex == null || indexOf(firstChild!) != 0) {
        return false;
      }
      if (_settleApproximateLayout(childConstraints, crossAxisCount)) {
        return true;
      }
      settled = true;
      scrollOffsets.fillRange(0, crossAxisCount, 0);
      earliestUsefulChild = firstChild;
      leadingChildWithLayout = firstChild;
      trailingChildWithLayout = lastChild;
      return false;
    }

    if (_anchorIndex != null &&
        constraints.scrollOffset < precisionErrorTolerance &&
        indexOf(firstChild!) > 0) {
      // Asked for the start of the grid, for example by jumping to the top:
      // the approximate positions cannot tell what is there, so switch to the
      // exact layout right away.
      while (indexOf(firstChild!) > 0) {
        if (insertAndLayoutLeadingChild(
              childConstraints,
              parentUsesSize: true,
            ) ==
            null) {
          break;
        }
      }
    }

    if (settleIfAtStart()) {
      return;
    }

    // Find the first child that is visible in the viewport.
    earliestUsefulChild = firstChild;
    while (!settled &&
        (_anchorIndex != null
                ? _maxFinite(scrollOffsets)
                : _max(scrollOffsets)) >
            scrollOffset) {
      // We have to add children before the earliestUsefulChild.
      earliestUsefulChild = insertAndLayoutLeadingChild(
        childConstraints,
        parentUsesSize: true,
      );

      if (earliestUsefulChild == null) {
        // There are no more child before the current firstChild.
        final childParentData = _getParentData(firstChild!);
        childParentData.layoutOffset = 0;

        if (scrollOffset == 0) {
          // insertAndLayoutLeadingChild only lays out the children before
          // firstChild. In this case, nothing has been laid out. We have
          // to lay out firstChild manually.
          firstChild!.layout(childConstraints, parentUsesSize: true);
          earliestUsefulChild = firstChild;
          leadingChildWithLayout = earliestUsefulChild;
          trailingChildWithLayout ??= earliestUsefulChild;
          break;
        } else {
          // We ran out of children before reaching the scroll offset.
          // We must inform our parent that this sliver cannot fulfill
          // its contract and that we need a scroll offset correction.
          geometry = SliverGeometry(scrollOffsetCorrection: -scrollOffset);
          return;
        }
      }

      final earliestScrollOffset = _min(scrollOffsets);

      // firstChildScrollOffset may contain double precision error
      if (earliestScrollOffset < -precisionErrorTolerance) {
        // Let's assume there is no child before the first child. We will
        // correct it on the next layout if it is not.
        geometry = SliverGeometry(
          scrollOffsetCorrection: -earliestScrollOffset,
        );
        final childParentData = _getParentData(firstChild!);
        final compute = computeFirstChildParentData();
        childParentData.apply(compute);
        childParentData.layoutOffset = 0;
        return;
      }

      final firstChildParentData = computeFirstChildParentData();
      final childParentData = _getParentData(earliestUsefulChild!);
      childParentData.apply(firstChildParentData);
      // Don't forget to update the earliestScrollOffsets.
      scrollOffsets[firstChildParentData.crossAxisIndex!] =
          firstChildParentData.layoutOffset!;
      assert(earliestUsefulChild == firstChild);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout ??= earliestUsefulChild;

      if (_anchorIndex != null) {
        if (settleIfAtStart()) {
          return;
        }
        if (!settled &&
            firstChildParentData.layoutOffset! < -precisionErrorTolerance) {
          // Approximate positions ran past the start: make room.
          _shiftChildren(-firstChildParentData.layoutOffset!);
          return;
        }
      }
    }

    assert(childScrollOffset(firstChild!)! > -precisionErrorTolerance);

    // If the scroll offset is at zero, we should make sure we are
    // actually at the beginning of the list.
    if (scrollOffset < precisionErrorTolerance && _anchorIndex != null) {
      // Same as below, for approximately placed children.
      while (indexOf(firstChild!) > 0) {
        final inserted = insertAndLayoutLeadingChild(
          childConstraints,
          parentUsesSize: true,
        );
        assert(inserted != null);
        final data = computeFirstChildParentData();
        _getParentData(inserted!).apply(data);
        scrollOffsets[data.crossAxisIndex!] = data.layoutOffset!;
        earliestUsefulChild = inserted;
        leadingChildWithLayout = inserted;
        if (settleIfAtStart()) {
          return;
        }
        if (settled) {
          break;
        }
        if (data.layoutOffset! < -precisionErrorTolerance) {
          _shiftChildren(-data.layoutOffset!);
          return;
        }
      }
    } else if (scrollOffset < precisionErrorTolerance) {
      // We iterate from the firstChild in case the leading child has a 0
      // paint extent.
      while (indexOf(firstChild!) > 0) {
        final childParentData = _getParentData(firstChild!);
        // We correct one child at a time. If there are more children before
        // the earliestUsefulChild, we will correct it once the scroll offset
        // reaches zero again.
        earliestUsefulChild = insertAndLayoutLeadingChild(
          childConstraints,
          parentUsesSize: true,
        );
        assert(earliestUsefulChild != null);
        final firstChildParentData = computeFirstChildParentData();
        childParentData.apply(firstChildParentData);
        final firstChildScrollOffset = firstChildParentData.layoutOffset!;
        // We only need to correct if the leading child actually has a
        // paint extent.
        if (firstChildScrollOffset < -precisionErrorTolerance) {
          geometry = SliverGeometry(
            scrollOffsetCorrection: -firstChildScrollOffset,
          );
          return;
        }
      }
    }

    // At this point, earliestUsefulChild is the first child, and is a child
    // whose scrollOffset is at or before the scrollOffset, and
    // leadingChildWithLayout and trailingChildWithLayout are either null or
    // cover a range of render boxes that we have laid out with the first being
    // the same as earliestUsefulChild and the last being either at or after the
    // scroll offset.

    assert(earliestUsefulChild == firstChild);
    assert(childScrollOffset(earliestUsefulChild!)! <= scrollOffset);

    // Make sure we've laid out at least one child.
    if (leadingChildWithLayout == null) {
      earliestUsefulChild!.layout(childConstraints, parentUsesSize: true);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout = earliestUsefulChild;
    }

    // Here, earliestUsefulChild is still the first child, it's got a
    // scrollOffset that is at or before our actual scrollOffset, and it has
    // been laid out, and is in fact our leadingChildWithLayout. It's possible
    // that some children beyond that one have also been laid out.
    final leadingScrollOffset = _min(scrollOffsets);

    bool inLayoutRange = true;
    child = earliestUsefulChild;
    int index = indexOf(child!);

    // From now on, the scrollOffsets will be the next possible scroll offsets
    // for new children.
    // As earliestUsefulChild is already laid out, we start by updating the
    // scroll offsets for the next children.
    scrollOffsets[_childCrossAxisIndex(child)!] =
        childScrollOffset(child)! + paintExtentOf(child) + mainAxisSpacing;

    // We also make sure that any infinite scroll offset is set now.
    final anchorFrontier = _isApproximate(child) ? _anchorFrontier : null;
    for (int i = 0; i < scrollOffsets.length; i++) {
      if (scrollOffsets[i] == double.infinity) {
        scrollOffsets[i] = anchorFrontier?[i] ?? 0.0;
      }
    }

    // Returns true if we advanced, false if we have no more children
    bool advance() {
      assert(child != null);
      if (child == trailingChildWithLayout) {
        inLayoutRange = false;
      }
      child = childAfter(child!);
      if (child == null) {
        inLayoutRange = false;
      }
      index += 1;
      if (!inLayoutRange) {
        if (child == null || indexOf(child!) != index) {
          // We are missing a child. Insert it (and lay it out) if possible.
          child = insertAndLayoutChild(
            childConstraints,
            after: trailingChildWithLayout,
            parentUsesSize: true,
          );
          if (child == null) {
            // We have run out of children.
            return false;
          }
        } else {
          // Lay out the child.
          child!.layout(childConstraints, parentUsesSize: true);
        }
        trailingChildWithLayout = child;
      }
      assert(child != null);
      positionChild(child!);
      assert(indexOf(child!) == index);
      return true;
    }

    // Find the first child that ends after the scroll offset.
    // Equivalent to "every column ends before scrollOffset".
    while (_max(scrollOffsets) - mainAxisSpacing < scrollOffset) {
      leadingGarbage += 1;
      if (!advance()) {
        assert(leadingGarbage == childCount);
        assert(child == null);
        // we want to make sure we keep the last child around so we know the end scroll offset
        collectGarbage(leadingGarbage - 1, 0);
        assert(firstChild == lastChild);
        final double extent = _max(scrollOffsets) - mainAxisSpacing;
        geometry = SliverGeometry(scrollExtent: extent, maxPaintExtent: extent);
        return;
      }
    }

    // Now find the first child that ends after our end.
    // Equivalent to "any column ends before targetEndScrollOffset".
    while (_min(scrollOffsets) - mainAxisSpacing < targetEndScrollOffset) {
      if (!advance()) {
        reachedEnd = true;
        break;
      }
    }

    // Finally count up all the remaining children and label them as garbage.
    if (child != null) {
      child = childAfter(child!);
      while (child != null) {
        trailingGarbage += 1;
        child = childAfter(child!);
      }
    }

    // At this point everything should be good to go, we just have to clean up
    // the garbage and report the geometry.
    collectGarbage(leadingGarbage, trailingGarbage);

    assert(debugAssertChildListIsNonEmptyAndContiguous());
    final endScrollOffset = _max(scrollOffsets) - mainAxisSpacing;
    final double estimatedMaxScrollOffset;
    if (reachedEnd) {
      estimatedMaxScrollOffset = endScrollOffset;
    } else {
      estimatedMaxScrollOffset = childManager.estimateMaxScrollOffset(
        constraints,
        firstIndex: indexOf(firstChild!),
        lastIndex: indexOf(lastChild!),
        leadingScrollOffset: leadingScrollOffset,
        trailingScrollOffset: endScrollOffset,
      );
      assert(estimatedMaxScrollOffset >= endScrollOffset - leadingScrollOffset);
    }
    final double paintExtent = calculatePaintOffset(
      constraints,
      from: leadingScrollOffset,
      to: endScrollOffset,
    );
    final double cacheExtent = calculateCacheOffset(
      constraints,
      from: leadingScrollOffset,
      to: endScrollOffset,
    );
    final double targetEndScrollOffsetForPaint =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    geometry = SliverGeometry(
      scrollExtent: estimatedMaxScrollOffset,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: estimatedMaxScrollOffset,
      // Conservative to avoid flickering away the clip during scroll.
      hasVisualOverflow:
          endScrollOffset > targetEndScrollOffsetForPaint ||
          constraints.scrollOffset > 0.0,
    );

    // We may have started the layout while scrolled to the end, which would not
    // expose a new child.
    if (estimatedMaxScrollOffset == endScrollOffset) {
      childManager.setDidUnderflow(true);
    }
    childManager.didFinishLayout();
  }
}

// Allocation-free scans used in the layout hot path instead of closure-based
// `any`/`every`/`reduce`.

double _min(List<double> values) {
  double result = values[0];
  for (int i = 1; i < values.length; i++) {
    final value = values[i];
    if (value < result) {
      result = value;
    }
  }
  return result;
}

double _max(List<double> values) {
  double result = values[0];
  for (int i = 1; i < values.length; i++) {
    final value = values[i];
    if (value > result) {
      result = value;
    }
  }
  return result;
}

/// The maximum of the finite [values], or negative infinity if there is none.
double _maxFinite(List<double> values) {
  double result = double.negativeInfinity;
  for (int i = 0; i < values.length; i++) {
    final value = values[i];
    if (value.isFinite && value > result) {
      result = value;
    }
  }
  return result;
}

/// The smallest index of the maximum finite value in [values], or 0 if there
/// is none.
int _indexOfMaxFinite(List<double> values) {
  int index = 0;
  double max = double.negativeInfinity;
  for (int i = 0; i < values.length; i++) {
    final value = values[i];
    if (value.isFinite && value > max) {
      max = value;
      index = i;
    }
  }
  return index;
}

bool _anyInfinite(List<double> values) {
  for (int i = 0; i < values.length; i++) {
    if (values[i].isInfinite) {
      return true;
    }
  }
  return false;
}

extension on SliverMasonryGridParentData {
  void applyZero() {
    layoutOffset = 0.0;
    crossAxisIndex = 0;
  }

  void apply(SliverMasonryGridParentData parentData) {
    layoutOffset = parentData.layoutOffset;
    crossAxisIndex = parentData.crossAxisIndex;
  }
}
