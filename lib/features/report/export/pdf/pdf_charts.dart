/// Charts drawn straight into the PDF as vector graphics.
///
/// Drawn with the PDF canvas rather than captured from the screen, so the report builds with no
/// widget tree, stays sharp at any zoom and is the same on every device. They carry the same
/// things as the on-screen charts: the baseline median, the usual-spread band, hollow markers
/// for tests that were set aside, the smoothed line, and the population band only when it has a
/// source. Colour is never the only cue -- each area has its own marker shape, set-aside tests
/// are hollow, and the legend line spells it all out in words.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../engine/features.dart';

/// The colour-blind-safe colour of each area, matching the app.
const Map<Domain, PdfColor> kPdfDomainColors = {
  Domain.cognitive: PdfColor.fromInt(0xFF0072B2),
  Domain.speech: PdfColor.fromInt(0xFFCC79A7),
  Domain.motor: PdfColor.fromInt(0xFFD55E00),
  Domain.interaction: PdfColor.fromInt(0xFF009E73),
};

/// A marker shape per area, so the charts do not rely on colour alone.
enum MarkerShape { circle, square, triangle, diamond }

MarkerShape markerFor(Domain domain) => switch (domain) {
  Domain.cognitive => MarkerShape.circle,
  Domain.speech => MarkerShape.diamond,
  Domain.motor => MarkerShape.triangle,
  Domain.interaction => MarkerShape.square,
};

/// One test on a chart.
class ChartPoint {
  const ChartPoint({required this.value, required this.counted});

  final double value;

  /// False for a test that was set aside: drawn hollow.
  final bool counted;
}

/// A horizontal guide with a label, e.g. the mild or notable level.
class ChartGuide {
  const ChartGuide({required this.y, required this.label});

  final double y;
  final String label;
}

const double _labelWidth = 46;

/// Width of the chart area, from the A4 text width of the report's pages.
const double kChartWidth = 465;

PdfColor _tint(PdfColor color, double amount) => PdfColor(
  color.red + (1 - color.red) * amount,
  color.green + (1 - color.green) * amount,
  color.blue + (1 - color.blue) * amount,
);

/// A line chart of [points] (oldest first, spaced evenly in test order).
///
/// [median] and [spread] draw the baseline line and the usual-spread band; [smoothed] gives one
/// value per *counted* point. [population] is drawn only when the caller has a validated range.
pw.Widget pdfLineChart({
  required List<ChartPoint> points,
  required Domain domain,
  required String Function(double) format,
  required String firstDate,
  required String lastDate,
  double? median,
  double? spread,
  List<double> smoothed = const [],
  ({double low, double high})? population,
  List<ChartGuide> guides = const [],
  double height = 120,
}) {
  final color = kPdfDomainColors[domain]!;
  final shape = markerFor(domain);

  final ys = <double>[
    for (final p in points) p.value,
    ...smoothed,
    ?median,
    if (median != null && spread != null) ...[median - spread, median + spread],
    if (population != null) ...[population.low, population.high],
    for (final g in guides) g.y,
  ];
  var low = ys.reduce((a, b) => a < b ? a : b);
  var high = ys.reduce((a, b) => a > b ? a : b);
  if ((high - low).abs() < 1e-9) {
    low -= 1;
    high += 1;
  }
  final pad = (high - low) * 0.08;
  low -= pad;
  high += pad;

  double yOf(double v, PdfPoint size) => (v - low) / (high - low) * size.y;
  double xOf(int i, PdfPoint size) {
    const inset = 8.0;
    if (points.length <= 1) return size.x / 2;
    return inset + i / (points.length - 1) * (size.x - 2 * inset);
  }

  void marker(PdfGraphics g, double x, double y, bool filled) {
    const r = 3.6;
    g
      ..setStrokeColor(color)
      ..setFillColor(filled ? color : PdfColors.white)
      ..setLineWidth(1.2);
    switch (shape) {
      case MarkerShape.circle:
        g.drawEllipse(x, y, r, r);
      case MarkerShape.square:
        g.drawRect(x - r, y - r, 2 * r, 2 * r);
      case MarkerShape.triangle:
        g
          ..moveTo(x, y + r + 0.6)
          ..lineTo(x + r + 0.6, y - r)
          ..lineTo(x - r - 0.6, y - r)
          ..closePath();
      case MarkerShape.diamond:
        g
          ..moveTo(x, y + r + 1)
          ..lineTo(x + r + 1, y)
          ..lineTo(x, y - r - 1)
          ..lineTo(x - r - 1, y)
          ..closePath();
    }
    g.fillAndStrokePath();
  }

  final painter = pw.CustomPaint(
    size: PdfPoint(kChartWidth - _labelWidth, height),
    painter: (g, size) {
      // Frame.
      g
        ..setStrokeColor(PdfColors.grey400)
        ..setLineWidth(0.6)
        ..drawRect(0, 0, size.x, size.y)
        ..strokePath();

      // Population band, context only: grey, bordered with dashes so it is not a colour cue.
      if (population != null) {
        g
          ..setFillColor(PdfColors.grey200)
          ..drawRect(
            0,
            yOf(population.low, size),
            size.x,
            yOf(population.high, size) - yOf(population.low, size),
          )
          ..fillPath()
          ..setStrokeColor(PdfColors.grey600)
          ..setLineWidth(0.6)
          ..setLineDashPattern([2, 2])
          ..moveTo(0, yOf(population.low, size))
          ..lineTo(size.x, yOf(population.low, size))
          ..moveTo(0, yOf(population.high, size))
          ..lineTo(size.x, yOf(population.high, size))
          ..strokePath()
          ..setLineDashPattern();
      }

      // The usual-spread band around the baseline, then the baseline itself.
      if (median != null && spread != null) {
        g
          ..setFillColor(_tint(color, 0.82))
          ..drawRect(
            0,
            yOf(median - spread, size),
            size.x,
            yOf(median + spread, size) - yOf(median - spread, size),
          )
          ..fillPath();
      }
      if (median != null) {
        g
          ..setStrokeColor(PdfColors.grey800)
          ..setLineWidth(0.9)
          ..setLineDashPattern([5, 3])
          ..moveTo(0, yOf(median, size))
          ..lineTo(size.x, yOf(median, size))
          ..strokePath()
          ..setLineDashPattern();
      }

      // Guide lines (the mild and notable levels).
      for (final guide in guides) {
        g
          ..setStrokeColor(PdfColors.grey700)
          ..setLineWidth(0.7)
          ..setLineDashPattern([1.5, 2.5])
          ..moveTo(0, yOf(guide.y, size))
          ..lineTo(size.x, yOf(guide.y, size))
          ..strokePath()
          ..setLineDashPattern();
      }

      // The values, joined in order through the counted ones.
      final counted = [
        for (var i = 0; i < points.length; i++)
          if (points[i].counted) i,
      ];
      if (counted.length > 1) {
        g
          ..setStrokeColor(color)
          ..setLineWidth(1.4)
          ..moveTo(
            xOf(counted.first, size),
            yOf(points[counted.first].value, size),
          );
        for (final i in counted.skip(1)) {
          g.lineTo(xOf(i, size), yOf(points[i].value, size));
        }
        g.strokePath();
      }

      // The smoothed line, dotted, over the counted points.
      if (smoothed.length == counted.length && smoothed.length > 1) {
        g
          ..setStrokeColor(PdfColors.black)
          ..setLineWidth(1.0)
          ..setLineDashPattern([1, 2])
          ..moveTo(xOf(counted.first, size), yOf(smoothed.first, size));
        for (var k = 1; k < counted.length; k++) {
          g.lineTo(xOf(counted[k], size), yOf(smoothed[k], size));
        }
        g
          ..strokePath()
          ..setLineDashPattern();
      }

      for (var i = 0; i < points.length; i++) {
        marker(g, xOf(i, size), yOf(points[i].value, size), points[i].counted);
      }
    },
  );

  const labelStyle = pw.TextStyle(fontSize: 7, color: PdfColors.grey700);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: _labelWidth,
            height: height,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 4),
                  child: pw.Text(format(high), style: labelStyle),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 4),
                  child: pw.Text(format(low), style: labelStyle),
                ),
              ],
            ),
          ),
          painter,
        ],
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: _labelWidth, top: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(firstDate, style: labelStyle),
            pw.Text(lastDate, style: labelStyle),
          ],
        ),
      ),
    ],
  );
}

/// One stacked bar per test, each adding up to 100%, in the four area colours.
///
/// Each area keeps its own shade and, in the legend, its marker shape; the segments are also
/// labelled where wide enough, so the split can be read without telling the colours apart.
pw.Widget pdfShareBars({
  required List<Map<Domain, double>> shares,
  double height = 90,
}) {
  return pw.CustomPaint(
    size: PdfPoint(kChartWidth, height),
    painter: (g, size) {
      if (shares.isEmpty) return;
      final slot = size.x / shares.length;
      final barWidth = (slot * 0.7).clamp(2.0, 28.0);
      for (var i = 0; i < shares.length; i++) {
        var base = 0.0;
        final x = i * slot + (slot - barWidth) / 2;
        for (final domain in Domain.values) {
          final share = shares[i][domain] ?? 0;
          final h = share * size.y;
          if (h <= 0) continue;
          g
            ..setFillColor(kPdfDomainColors[domain]!)
            ..drawRect(x, base, barWidth, h)
            ..fillPath()
            ..setStrokeColor(PdfColors.white)
            ..setLineWidth(0.5)
            ..drawRect(x, base, barWidth, h)
            ..strokePath();
          base += h;
        }
      }
      g
        ..setStrokeColor(PdfColors.grey400)
        ..setLineWidth(0.6)
        ..drawRect(0, 0, size.x, size.y)
        ..strokePath();
    },
  );
}
