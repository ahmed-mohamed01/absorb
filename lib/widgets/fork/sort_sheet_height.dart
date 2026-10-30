import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../library_sort_filter_sheet.dart' show LibraryTab;

// Fork-owned: the height of the Library tab's sort and filter sheet
// (library_sort_filter_sheet.dart), so its sort list and the Collapse
// series switch fit instead of being clipped at upstream's fixed height
// (440, or 420 with a filter section open). See FORK_NOTES.md.

// The sort tab's layout, as upstream draws it. `SheetOption` rows: 10 above
// and below, a 20pt icon beside 14pt text, 4 under each. The list has 12
// above and below. The Collapse series row keeps the switch's 48 tap target.
const double _optionVPad = 10;
const double _optionIcon = 20;
const double _optionText = 14;
const double _optionGap = 4;
const double _listVPad = 12;
const double _switchTarget = 48;

/// A line of text's height over its font size: M3 body text's 20/14,
/// rounded up a touch so the estimate errs tall.
const double _lineHeight = 1.45;

/// The share of the screen the sheet's body may take before it scrolls.
const double _maxScreenShare = 0.7;

/// Whether the sort tab shows the Collapse series switch: on the Library
/// tab of a book library.
bool forkLibraryHasCollapseSwitch(LibraryTab tab, {required bool podcast}) =>
    tab == LibraryTab.library && !podcast;

/// The sort and filter sheet's body height. On the Library tab it is tall
/// enough for [rows] sort options and the Collapse series switch under
/// them, at the current text size; never shorter than [upstream] (the
/// filter tab shares the height) and no taller than most of the screen,
/// where the list scrolls instead. Other tabs keep [upstream].
double forkLibrarySortHeight(BuildContext context, double upstream,
    {required LibraryTab tab, required bool podcast, required int rows}) {
  if (tab != LibraryTab.library) return upstream;
  final line = MediaQuery.textScalerOf(context).scale(_optionText) * _lineHeight;
  final double row = 2 * _optionVPad + math.max(_optionIcon, line) + _optionGap;
  final double switchRow = 2 * _optionVPad + math.max(_switchTarget, line) + _optionGap;
  final double fitted = 2 * _listVPad +
      rows * row +
      (forkLibraryHasCollapseSwitch(tab, podcast: podcast) ? switchRow : 0.0);
  final room = MediaQuery.sizeOf(context).height * _maxScreenShare;
  return math.max(upstream, math.min(fitted, room));
}
