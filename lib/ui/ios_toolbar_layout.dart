import 'dart:math' as math;

const double _iosTabletToolbarActionExtent = 44;
const double _iosTabletFixedToolbarExtent = 56;
const double _iosTabletMoreActionExtent = 44;

List<String> iosPhoneVisibleToolbarActions({
  required Iterable<String> selectedActions,
  required List<String> availableActions,
  int maximumDirectActions = 3,
}) {
  if (maximumDirectActions <= 0) return <String>[];

  final normalizedSelection = <String>[];
  for (final action in selectedActions) {
    if (availableActions.contains(action) &&
        !normalizedSelection.contains(action)) {
      normalizedSelection.add(action);
    }
  }
  return normalizedSelection.take(maximumDirectActions).toList(growable: false);
}

List<String> iosTabletVisibleToolbarActions({
  required Iterable<String> selectedActions,
  required List<String> availableActions,
  required double newsPaneWidth,
}) {
  final normalizedSelection = <String>[];
  for (final action in selectedActions) {
    if (availableActions.contains(action) &&
        !normalizedSelection.contains(action)) {
      normalizedSelection.add(action);
    }
  }
  if (normalizedSelection.isEmpty || newsPaneWidth <= 0) {
    return <String>[];
  }

  final titleReservation =
      (newsPaneWidth * 0.44).clamp(240.0, 320.0).toDouble();
  final widthWithoutMore = math.max(
    0.0,
    newsPaneWidth - titleReservation - _iosTabletFixedToolbarExtent,
  );
  final allActionsSelected =
      normalizedSelection.length == availableActions.length;
  final allActionsFitWithoutMore = allActionsSelected &&
      normalizedSelection.length * _iosTabletToolbarActionExtent <=
          widthWithoutMore;
  final availableDirectWidth = math.max(
    0.0,
    widthWithoutMore -
        (allActionsFitWithoutMore ? 0 : _iosTabletMoreActionExtent),
  );
  final capacity = availableDirectWidth ~/ _iosTabletToolbarActionExtent;
  return normalizedSelection.take(capacity).toList(growable: false);
}
