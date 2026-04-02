import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../services/supabase_service.dart';

/// Recent PDF/CSV exports (rows from `export_history`).
class ExportHistoryScreen extends StatefulWidget {
  const ExportHistoryScreen({super.key});

  @override
  State<ExportHistoryScreen> createState() => _ExportHistoryScreenState();
}

class _ExportHistoryScreenState extends State<ExportHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = SupabaseService.fetchExportHistory();
  }

  Future<void> _reload() async {
    setState(() {
      _future = SupabaseService.fetchExportHistory();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export history'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load history: ${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No exports yet. Run a PDF or CSV export from Settings to see it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BillyTheme.gray500, fontSize: 15),
                ),
              ),
            );
          }
          final dateFmt = DateFormat.yMMMd();
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: rows.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = rows[i];
                final format = (r['format'] as String? ?? '').toUpperCase();
                final start = r['date_range_start'] as String? ?? '';
                final end = r['date_range_end'] as String? ?? '';
                final createdRaw = r['created_at'] as String?;
                final created = createdRaw != null ? DateTime.tryParse(createdRaw) : null;
                final createdLabel = created != null ? dateFmt.format(created.toLocal()) : '—';
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: BillyTheme.gray100),
                    ),
                    leading: Icon(
                      format == 'PDF' ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined,
                      color: BillyTheme.emerald600,
                    ),
                    title: Text('$format · $start → $end', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Exported $createdLabel'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
