import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'reader_content.dart' show readerIllustrationUrl;

/// One paragraph slice placed on a page. [start]/[end] are UTF-16 ranges into
/// `paragraphs[paragraph]`; a whole paragraph uses `0` and `text.length`.
class ReaderPageSlice {
  const ReaderPageSlice(this.paragraph, this.start, this.end);
  final int paragraph;
  final int start;
  final int end;
}

/// Page layout for one chapter in the horizontal reader mode.
class ReaderPagination {
  const ReaderPagination(this.pages, this._firstPageOf);
  final List<List<ReaderPageSlice>> pages;
  final Map<int, int> _firstPageOf;

  int get pageCount => pages.length;

  /// First page containing [paragraph]; clamped to the last page.
  int pageOfParagraph(int paragraph) =>
      _firstPageOf[paragraph] ?? pages.length - 1;
}

/// Measures [paragraphs] into fixed pages with the same text metrics the
/// reader paints, so a page never overflows: whole paragraphs pack while they
/// fit and long ones split at rendered line boundaries.
///
/// Illustration paragraphs keep the scroll-mode slot height
/// `(maxWidth - 52) * 4 / 3`; blank separators cost nothing.
ReaderPagination paginateReaderParagraphs({
  required List<String> paragraphs,
  required double maxWidth,
  required double maxHeight,
  required TextStyle style,
  required TextScaler textScaler,
  double paragraphSpacing = 16,
}) {
  final height = math.max(120.0, maxHeight);
  final width = math.max(120.0, maxWidth);
  final pages = <List<ReaderPageSlice>>[<ReaderPageSlice>[]];
  final firstPage = <int, int>{};
  var used = 0.0;

  void newPage() {
    pages.add(<ReaderPageSlice>[]);
    used = 0;
  }

  void emit(int paragraph, int start, int end, double consumed) {
    firstPage.putIfAbsent(paragraph, () => pages.length - 1);
    pages.last.add(ReaderPageSlice(paragraph, start, end));
    used += consumed;
  }

  for (var index = 0; index < paragraphs.length; index++) {
    final text = paragraphs[index];
    if (text.isEmpty) {
      emit(index, 0, 0, 0);
      continue;
    }
    if (readerIllustrationUrl(text) != null || text.trim() == '[插图]') {
      final slot = (width - 52) * 4 / 3;
      if (used > 0 && used + paragraphSpacing + slot > height) newPage();
      emit(
        index,
        0,
        text.length,
        (pages.last.isEmpty ? 0 : paragraphSpacing) + slot,
      );
      continue;
    }
    final layout = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    try {
      if (layout.height <= 0) {
        emit(index, 0, text.length, 0);
        continue;
      }
      final leading = pages.last.isEmpty ? 0 : paragraphSpacing;
      if (leading + layout.height <= height - used) {
        emit(index, 0, text.length, leading + layout.height);
        continue;
      }
      // Split the paragraph at rendered line boundaries. Each emitted slice
      // must advance `start` so the loop always terminates.
      final lines = layout.computeLineMetrics();
      final starts = <int>[for (var i = 0; i < lines.length; i++) 0];
      for (var i = 1; i < lines.length; i++) {
        starts[i] = layout
            .getPositionForOffset(
              Offset(1, lines[i].baseline - lines[i].ascent + 1),
            )
            .offset;
      }
      var line = 0;
      var start = 0;
      while (line < lines.length) {
        var spacing = pages.last.isEmpty ? 0 : paragraphSpacing;
        var capacity = height - used - spacing;
        var measured = 0.0;
        var taken = line;
        while (taken < lines.length && measured + lines[taken].height <= capacity + .01) {
          measured += lines[taken].height;
          taken++;
        }
        if (taken == line && pages.last.isNotEmpty) {
          // A single line taller than the remaining space starts a fresh page;
          // only a line taller than a whole page would still not fit.
          newPage();
          spacing = 0;
          capacity = height;
          while (taken < lines.length && measured + lines[taken].height <= capacity + .01) {
            measured += lines[taken].height;
            taken++;
          }
        }
        if (taken == line) taken = line + 1; // guarantee progress
        var end = taken >= lines.length
            ? text.length
            : math.max(start + 1, starts[taken]);
        if (end <= start) end = start + 1;
        if (end > text.length) end = text.length;
        emit(index, start, end, spacing + measured);
        start = end;
        line = taken;
      }
    } finally {
      layout.dispose();
    }
  }
  return ReaderPagination(List.unmodifiable(pages), Map.unmodifiable(firstPage));
}
