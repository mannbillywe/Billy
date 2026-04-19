// Optional chart payloads from `goat_mode_snapshots.summary_json["charts"]`.
// See docs/GOAT_MODE_CHARTS_AND_REPORTS_SPEC.md for the backend contract.

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

class GoatChartTimeseriesSpec {
  const GoatChartTimeseriesSpec({
    required this.id,
    required this.title,
    required this.unit,
    required this.points,
  });

  final String id;
  final String title;
  final String? unit;

  /// (ISO date or label, value)
  final List<(String, double)> points;

  static GoatChartTimeseriesSpec? tryParse(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final title = m['title']?.toString() ?? '';
    if (id.isEmpty || title.isEmpty) return null;
    final raw = m['points'];
    if (raw is! List) return null;
    final pts = <(String, double)>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final map = e.cast<String, dynamic>();
      final d = map['d']?.toString() ?? map['date']?.toString() ?? '';
      final v = _asDouble(map['v'] ?? map['value']);
      if (d.isEmpty || v == null) continue;
      pts.add((d, v));
    }
    if (pts.isEmpty) return null;
    return GoatChartTimeseriesSpec(
      id: id,
      title: title,
      unit: m['unit']?.toString(),
      points: pts,
    );
  }
}

class GoatChartBarGroupSpec {
  const GoatChartBarGroupSpec({
    required this.id,
    required this.title,
    required this.unit,
    required this.items,
  });

  final String id;
  final String title;
  final String? unit;
  final List<(String label, double value)> items;

  static GoatChartBarGroupSpec? tryParse(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final title = m['title']?.toString() ?? '';
    if (id.isEmpty || title.isEmpty) return null;
    final raw = m['items'];
    if (raw is! List) return null;
    final items = <(String, double)>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final map = e.cast<String, dynamic>();
      final label = map['label']?.toString() ?? '';
      final v = _asDouble(map['value']);
      if (label.isEmpty || v == null) continue;
      items.add((label, v));
    }
    if (items.isEmpty) return null;
    return GoatChartBarGroupSpec(
      id: id,
      title: title,
      unit: m['unit']?.toString(),
      items: items,
    );
  }
}

/// Parsed `summary_json["charts"]` when the backend includes it.
class GoatChartBundle {
  const GoatChartBundle({
    required this.version,
    required this.timeseries,
    required this.barGroups,
  });

  final int version;
  final List<GoatChartTimeseriesSpec> timeseries;
  final List<GoatChartBarGroupSpec> barGroups;

  static GoatChartBundle? tryParse(Map<String, dynamic> summary) {
    final raw = summary['charts'];
    if (raw is! Map<String, dynamic>) return null;
    final v = _asInt(raw['version']) ?? 1;
    final ts = <GoatChartTimeseriesSpec>[];
    final tRaw = raw['timeseries'];
    if (tRaw is List) {
      for (final e in tRaw) {
        if (e is Map<String, dynamic>) {
          final p = GoatChartTimeseriesSpec.tryParse(e);
          if (p != null) ts.add(p);
        } else if (e is Map) {
          final p = GoatChartTimeseriesSpec.tryParse(e.cast<String, dynamic>());
          if (p != null) ts.add(p);
        }
      }
    }
    final bars = <GoatChartBarGroupSpec>[];
    final bRaw = raw['bars'];
    if (bRaw is List) {
      for (final e in bRaw) {
        if (e is Map<String, dynamic>) {
          final p = GoatChartBarGroupSpec.tryParse(e);
          if (p != null) bars.add(p);
        } else if (e is Map) {
          final p = GoatChartBarGroupSpec.tryParse(e.cast<String, dynamic>());
          if (p != null) bars.add(p);
        }
      }
    }
    if (ts.isEmpty && bars.isEmpty) return null;
    return GoatChartBundle(version: v, timeseries: ts, barGroups: bars);
  }

  GoatChartTimeseriesSpec? timeseriesById(String id) {
    for (final t in timeseries) {
      if (t.id == id) return t;
    }
    return null;
  }
}
