import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';
import '../models/document_list_models.dart';
import 'document_detail_screen.dart';

/// Full list of saved documents with search, filters, and sort.
class DocumentsHistoryScreen extends ConsumerStatefulWidget {
  const DocumentsHistoryScreen({super.key});

  @override
  ConsumerState<DocumentsHistoryScreen> createState() => _DocumentsHistoryScreenState();
}

class _DocumentsHistoryScreenState extends ConsumerState<DocumentsHistoryScreen> {
  final _searchCtrl = TextEditingController();
  DocumentSourceFilter _filter = DocumentSourceFilter.all;
  DocumentSortMode _sort = DocumentSortMode.newest;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('All documents'),
        backgroundColor: BillyTheme.scaffoldBg,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
      ),
      body: docsAsync.when(
        data: (docs) {
          final filtered = filterAndSortDocuments(
            docs,
            searchQuery: _searchCtrl.text,
            filter: _filter,
            sort: _sort,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by vendor',
                    prefixIcon: const Icon(Icons.search, color: BillyTheme.gray400),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: BillyTheme.gray50),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: BillyTheme.gray50),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: DocumentSourceFilter.values.map((f) {
                    final selected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: FilterChip(
                        label: Text(f.label),
                        selected: selected,
                        onSelected: (_) => setState(() => _filter = f),
                        selectedColor: BillyTheme.emerald100,
                        checkmarkColor: BillyTheme.emerald700,
                      ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Text('Sort: ', style: TextStyle(color: BillyTheme.gray500, fontSize: 13)),
                    Expanded(
                      child: DropdownButtonFormField<DocumentSortMode>(
                        value: _sort,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: BillyTheme.gray50),
                          ),
                        ),
                        items: DocumentSortMode.values
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _sort = v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyHistory(hasAnyDocs: docs.isNotEmpty)
                    : RefreshIndicator(
                        color: BillyTheme.emerald600,
                        onRefresh: () => ref.read(documentsProvider.notifier).refresh(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final d = filtered[i];
                            final id = d['id'] as String? ?? '';
                            return _DocumentListTile(
                              doc: d,
                              currencyCode: currency,
                              onTap: id.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => DocumentDetailScreen(documentId: id),
                                        ),
                                      );
                                    },
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: BillyTheme.emerald600)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: BillyTheme.red500),
                const SizedBox(height: 12),
                Text('Could not load documents', style: TextStyle(color: BillyTheme.gray800, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('$e', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: BillyTheme.gray500)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => ref.invalidate(documentsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.hasAnyDocs});

  /// True when filters/search hid everything but DB has rows.
  final bool hasAnyDocs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: BillyTheme.gray300),
            const SizedBox(height: 16),
            Text(
              hasAnyDocs ? 'No matches' : 'No documents yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
            ),
            const SizedBox(height: 8),
            Text(
              hasAnyDocs
                  ? 'Try another search or filter.'
                  : 'Scan a receipt or add a bill from the home screen.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: BillyTheme.gray500, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentListTile extends StatelessWidget {
  const _DocumentListTile({
    required this.doc,
    required this.currencyCode,
    this.onTap,
  });

  final Map<String, dynamic> doc;
  final String? currencyCode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vendor = doc['vendor_name'] as String? ?? 'Unknown';
    final amount = (doc['amount'] as num?)?.toDouble() ?? 0;
    final dateStr = doc['date'] as String? ?? '';
    final type = doc['type'] as String? ?? 'receipt';
    final desc = doc['description'] as String? ?? '';
    final category = desc.isNotEmpty ? desc.split(',').first.trim() : 'Expense';
    final ocr = documentIsOcr(doc);

    String dateLabel = dateStr;
    try {
      final dt = DateTime.parse(dateStr);
      dateLabel = DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {}

    final chips = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: BillyTheme.gray100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          type == 'invoice' ? 'Invoice' : 'Receipt',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillyTheme.gray600),
        ),
      ),
      if (ocr)
        Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: BillyTheme.emerald50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'OCR',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillyTheme.emerald700),
          ),
        ),
    ];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray50),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: BillyTheme.emerald50,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  vendor.isNotEmpty ? vendor[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillyTheme.emerald600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$category • $dateLabel',
                      style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
                    ),
                    const SizedBox(height: 6),
                    Wrap(children: chips),
                  ],
                ),
              ),
              Text(
                AppCurrency.format(amount, currencyCode),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: BillyTheme.gray400, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
