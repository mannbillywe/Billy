import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/export_document.dart';
import '../services/csv_generator.dart';
import '../services/pdf_generator.dart';

/// Export screen - date range, format (PDF/CSV), generate and share
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    this.documents = const [],
  });

  final List<ExportDocument> documents;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _format = 'pdf';
  bool _isGenerating = false;
  String? _message;

  List<ExportDocument> get _filteredDocs {
    return widget.documents.where((d) {
      return !d.date.isBefore(_startDate) && !d.date.isAfter(_endDate);
    }).toList();
  }

  Future<void> _export() async {
    setState(() {
      _isGenerating = true;
      _message = null;
    });

    try {
      final docs = _filteredDocs;
      if (docs.isEmpty) {
        setState(() {
          _isGenerating = false;
          _message = 'No transactions in selected date range';
        });
        return;
      }

      if (_format == 'pdf') {
        final generator = PdfGenerator();
        final bytes = await generator.generateReport(
          documents: docs,
          startDate: _startDate,
          endDate: _endDate,
        );

        if (mounted) {
          await Printing.sharePdf(bytes: bytes, filename: 'billy-report-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf');
        }
      } else {
        final generator = CsvGenerator();
        final csv = generator.generate(
          documents: docs,
          startDate: _startDate,
          endDate: _endDate,
        );

        final filename = 'billy-export-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
        final xFile = XFile.fromData(
          Uint8List.fromList(utf8.encode(csv)),
          mimeType: 'text/csv',
          name: filename,
        );

        if (mounted) {
          await Share.shareXFiles([xFile], text: 'Billy expense export');
        }
      }

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _message = 'Export complete';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _message = 'Export failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: BillyTheme.zinc950),
        ),
        title: const Text(
          'Export Data',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: BillyTheme.zinc950,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Date Range',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: BillyTheme.zinc950,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateChip(
                    label: 'From',
                    date: _startDate,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _DateChip(
                    label: 'To',
                    date: _endDate,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: _startDate,
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _endDate = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Format',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: BillyTheme.zinc950,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FormatChip(
                    label: 'PDF',
                    isSelected: _format == 'pdf',
                    onTap: () => setState(() => _format = 'pdf'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _FormatChip(
                    label: 'CSV',
                    isSelected: _format == 'csv',
                    onTap: () => setState(() => _format = 'csv'),
                  ),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _message!.contains('failed') ? BillyTheme.red400.withOpacity(0.2) : BillyTheme.zinc100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _message!.contains('failed') ? BillyTheme.red500 : BillyTheme.zinc950,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 48),
            GestureDetector(
              onTap: _isGenerating ? null : _export,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: _isGenerating ? BillyTheme.zinc300 : BillyTheme.zinc950,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: _isGenerating ? null : [
                    BoxShadow(
                      color: BillyTheme.zinc300.withOpacity(0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _isGenerating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Text(
                        'Export & Share',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.02,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BillyTheme.zinc50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BillyTheme.zinc100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: BillyTheme.zinc400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dateFormat.format(date),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: BillyTheme.zinc950,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? BillyTheme.zinc950 : BillyTheme.zinc100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? BillyTheme.zinc950 : BillyTheme.zinc200),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: isSelected ? Colors.white : BillyTheme.zinc950,
          ),
        ),
      ),
    );
  }
}
