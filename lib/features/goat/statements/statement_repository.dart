import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../services/supabase_service.dart';
import 'statement_classification_service.dart';
import 'statement_dedupe.dart';
import 'statement_pdf_text_service.dart';
import 'statement_tabular_engine.dart';

String statementSourceTypeToDb(StatementFileKind k) => switch (k) {
      StatementFileKind.pdfDigital => 'pdf_digital',
      StatementFileKind.pdfScanned => 'pdf_scanned',
      StatementFileKind.csv => 'csv',
      StatementFileKind.xls => 'xls',
      StatementFileKind.xlsx => 'xlsx',
      StatementFileKind.image => 'image',
      StatementFileKind.unsupported => 'csv',
    };

String? amountRepresentationFromMapping(ColumnMapping m) {
  if (m.debitCol != null || m.creditCol != null) return 'debit_credit_columns';
  if (m.amountCol != null) return 'signed_amount';
  return null;
}

class StatementRepository {
  StatementRepository._();

  static SupabaseClient get _c => Supabase.instance.client;
  static String? get _uid => _c.auth.currentUser?.id;

  /// Mobile Safari often surfaces flaky cellular as [ClientException] / "Load failed".
  static bool _isLikelyTransientNetworkImport(Object e) {
    if (e is PostgrestException || e is AuthException) return false;
    final s = e.toString().toLowerCase();
    return s.contains('load failed') ||
        s.contains('failed to execute fetch') ||
        s.contains('clientexception') ||
        s.contains('socketexception') ||
        s.contains('connection reset') ||
        s.contains('connection closed') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('network is unreachable');
  }

  static Future<T> _retryImportNetwork<T>(Future<T> Function() run) async {
    Object? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await run();
      } catch (e, _) {
        last = e;
        if (!_isLikelyTransientNetworkImport(e) || attempt == 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 350 * (1 << attempt)));
      }
    }
    throw last ?? StateError('statement import retry');
  }

  static String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  static String storagePathFor({required String uid, required String importId, required String fileName}) {
    final now = DateTime.now();
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return '$uid/statements/${now.year}/${now.month.toString().padLeft(2, '0')}/$importId/$safe';
  }

  static Future<void> uploadToStorage(String path, Uint8List bytes, String contentType) async {
    await _c.storage.from('statement-files').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
  }

  static Future<Map<String, dynamic>?> findImportByHash(String fileHash) async {
    final uid = _uid;
    if (uid == null) return null;
    return _c
        .from('statement_imports')
        .select()
        .eq('user_id', uid)
        .eq('file_hash', fileHash)
        .inFilter('import_status', ['imported', 'parsed', 'needs_review'])
        .maybeSingle();
  }

  static Future<String> createImportRow({
    required String id,
    required String sourceType,
    required String fileName,
    required String storagePath,
    required String fileHash,
    String importStatus = 'uploaded',
    double? parseConfidence,
    int transactionCount = 0,
    String importMode = 'smart',
    Map<String, dynamic> metadata = const {},
    String? mimeType,
    String? sourceHint,
    String? documentFamily,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _c.from('statement_imports').insert({
      'id': id,
      'user_id': uid,
      'source_type': sourceType,
      'file_name': fileName,
      'storage_path': storagePath,
      'file_hash': fileHash,
      'import_status': importStatus,
      if (parseConfidence != null) 'parse_confidence': parseConfidence,
      'transaction_count': transactionCount,
      'import_mode': importMode,
      'metadata': metadata,
      'parser_version': 'billy-goat-statements-1',
      'extractor_version': 'billy-goat-extract-1',
      if (mimeType != null && mimeType.isNotEmpty) 'mime_type': mimeType,
      if (sourceHint != null && sourceHint.isNotEmpty) 'source_hint': sourceHint,
      if (documentFamily != null && documentFamily.isNotEmpty) 'document_family': documentFamily,
    });
    return id;
  }

  static Future<void> updateImport(
    String id, {
    String? importStatus,
    String? detectedInstitution,
    String? detectedAccountName,
    String? detectedAccountMask,
    DateTime? statementStartDate,
    DateTime? statementEndDate,
    int? transactionCount,
    double? parseConfidence,
    String? importMode,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final u = <String, dynamic>{};
    if (importStatus != null) u['import_status'] = importStatus;
    if (detectedInstitution != null) u['detected_institution'] = detectedInstitution;
    if (detectedAccountName != null) u['detected_account_name'] = detectedAccountName;
    if (detectedAccountMask != null) u['detected_account_mask'] = detectedAccountMask;
    if (statementStartDate != null) u['statement_start_date'] = _ymd(statementStartDate);
    if (statementEndDate != null) u['statement_end_date'] = _ymd(statementEndDate);
    if (transactionCount != null) u['transaction_count'] = transactionCount;
    if (parseConfidence != null) u['parse_confidence'] = parseConfidence;
    if (importMode != null) u['import_mode'] = importMode;
    if (errorMessage != null) u['error_message'] = errorMessage;
    if (metadata != null) u['metadata'] = metadata;
    if (u.isEmpty) return;
    await _c.from('statement_imports').update(u).eq('id', id).eq('user_id', uid);
  }

  static Future<void> updateImportExtended(
    String id, {
    double? openingBalance,
    double? closingBalance,
    double? totalDebit,
    double? totalCredit,
    String? amountRepresentation,
    String? documentFamily,
    String? accountHolderName,
    bool? hasRunningBalance,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final u = <String, dynamic>{};
    if (openingBalance != null) u['opening_balance'] = openingBalance;
    if (closingBalance != null) u['closing_balance'] = closingBalance;
    if (totalDebit != null) u['total_debit'] = totalDebit;
    if (totalCredit != null) u['total_credit'] = totalCredit;
    if (amountRepresentation != null) u['amount_representation'] = amountRepresentation;
    if (documentFamily != null) u['document_family'] = documentFamily;
    if (accountHolderName != null) u['account_holder_name'] = accountHolderName;
    if (hasRunningBalance != null) u['has_running_balance'] = hasRunningBalance;
    if (u.isEmpty) return;
    await _c.from('statement_imports').update(u).eq('id', id).eq('user_id', uid);
  }

  static const _rawExcerptMaxChars = 12000;

  static Future<String?> buildRawTextExcerpt(Uint8List bytes, StatementFormatDetection det) async {
    switch (det.kind) {
      case StatementFileKind.csv:
        final t = utf8.decode(bytes, allowMalformed: true);
        return t.length > _rawExcerptMaxChars ? t.substring(0, _rawExcerptMaxChars) : t;
      case StatementFileKind.pdfDigital:
      case StatementFileKind.pdfScanned:
        final g = await StatementPdfTextService.extractGrid(bytes);
        final buf = StringBuffer();
        for (final row in g.grid.take(250)) {
          buf.writeln(row.map((c) => c.replaceAll('\n', ' ')).join('\t'));
        }
        final s = buf.toString().trim();
        if (s.isEmpty) return null;
        return s.length > _rawExcerptMaxChars ? s.substring(0, _rawExcerptMaxChars) : s;
      case StatementFileKind.xlsx:
      case StatementFileKind.xls:
      case StatementFileKind.image:
      case StatementFileKind.unsupported:
        return null;
    }
  }

  /// Layer-1 audit row (raw text excerpt + metadata). Safe to call after [createImportRow].
  static Future<void> insertStatementRawExtraction({
    required String importId,
    String? rawText,
    Map<String, dynamic>? rawTables,
    Map<String, dynamic>? ocrJson,
    int? pageCount,
    Map<String, dynamic> extractionMeta = const {},
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('statement_raw_extractions').insert({
      'import_id': importId,
      'user_id': uid,
      'raw_text': rawText,
      'raw_tables': rawTables,
      'ocr_json': ocrJson,
      'page_count': pageCount,
      'extraction_meta': extractionMeta,
    });
  }

  static Future<void> persistRawExtractionLayer({
    required String importId,
    required Uint8List bytes,
    required StatementFormatDetection detection,
    StatementParseOutcome? parse,
    String? rawTextExcerpt,
  }) async {
    final excerpt = rawTextExcerpt ?? await buildRawTextExcerpt(bytes, detection);
    final meta = <String, dynamic>{
      'parser_version': 'billy-goat-statements-1',
      'file_kind': detection.kind.name,
      if (detection.note != null) 'detection_note': detection.note,
      if (parse != null) 'parse_confidence': parse.confidence,
      if (parse != null && parse.warnings.isNotEmpty) 'parse_warnings': parse.warnings,
    };
    await insertStatementRawExtraction(
      importId: importId,
      rawText: excerpt,
      extractionMeta: meta,
    );
  }

  static Future<void> insertStatementRowReview({
    required String importId,
    required int rowIndex,
    required String issueType,
    required String issueMessage,
    String? statementTransactionId,
    Map<String, dynamic> suggestedFix = const {},
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('statement_row_reviews').insert({
      'user_id': uid,
      'import_id': importId,
      'statement_transaction_id': statementTransactionId,
      'row_index': rowIndex,
      'issue_type': issueType,
      'issue_message': issueMessage,
      'suggested_fix': suggestedFix,
    });
  }

  static Future<List<Map<String, dynamic>>> fetchStatementRowReviews({
    String? importId,
    int limit = 200,
  }) async {
    final uid = _uid;
    if (uid == null) return [];
    var q = _c.from('statement_row_reviews').select().eq('user_id', uid);
    if (importId != null) {
      q = q.eq('import_id', importId);
    }
    final res = await q.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Registers upload + DB import row + raw audit rows (call before [commitParsedTransactions]).
  static Future<String> registerParsedImport({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required StatementFormatDetection detection,
    required StatementParseOutcome parse,
    String? sourceHint,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final hash = sha256Hex(bytes);
    final ex = await findImportByHash(hash);
    if (ex != null && ex['import_status'] == 'imported') {
      throw StateError('This file was already imported.');
    }
    final id = newImportId();
    final path = storagePathFor(uid: uid, importId: id, fileName: fileName);
    await uploadToStorage(path, bytes, contentType);
    await createImportRow(
      id: id,
      sourceType: statementSourceTypeToDb(detection.kind),
      fileName: fileName,
      storagePath: path,
      fileHash: hash,
      importStatus: 'parsed',
      parseConfidence: parse.confidence,
      transactionCount: parse.rows.length,
      metadata: {
        'warnings': parse.warnings,
        'detection_note': detection.note,
      },
      mimeType: contentType,
      sourceHint: sourceHint,
    );
    final payloads = parse.rows
        .map(
          (r) => {
            'row_index': r.rowIndex,
            'txn_date': _ymd(r.txnDate),
            'description': r.description,
            'amount': r.amount,
            'direction': r.direction,
            if (r.balance != null) 'balance': r.balance,
            if (r.reference != null) 'reference': r.reference,
          },
        )
        .toList();
    await insertRawRows(id, payloads);
    await updateImport(
      id,
      statementStartDate: parse.periodStart,
      statementEndDate: parse.periodEnd,
    );
    await updateImportExtended(
      id,
      openingBalance: parse.openingBalance,
      closingBalance: parse.closingBalance,
      amountRepresentation: amountRepresentationFromMapping(parse.mapping),
      hasRunningBalance: parse.mapping.balanceCol != null,
    );
    await persistRawExtractionLayer(importId: id, bytes: bytes, detection: detection, parse: parse);
    final excerpt = await buildRawTextExcerpt(bytes, detection);
    if (excerpt != null && excerpt.length > 200) {
      unawaited(StatementClassificationService.classifyImport(importId: id, textExcerpt: excerpt));
    }
    if (parse.confidence < 58) {
      await insertImportReview(
        importId: id,
        reviewType: 'low_parse_confidence',
        payload: {
          'confidence': parse.confidence,
          'row_count': parse.rows.length,
          'file_name': fileName,
        },
      );
    }
    return id;
  }

  /// Upload + import row in [needs_review] with an audit queue row (scanned PDF, empty parse, etc.).
  static Future<String> registerNeedsReviewImport({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required StatementFormatDetection detection,
    String reviewType = 'parse_failed',
    Map<String, dynamic> payload = const {},
    String? sourceHint,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final hash = sha256Hex(bytes);
    final id = newImportId();
    final path = storagePathFor(uid: uid, importId: id, fileName: fileName);
    await uploadToStorage(path, bytes, contentType);
    await createImportRow(
      id: id,
      sourceType: statementSourceTypeToDb(detection.kind),
      fileName: fileName,
      storagePath: path,
      fileHash: hash,
      importStatus: 'needs_review',
      transactionCount: 0,
      parseConfidence: 0,
      metadata: {
        'detection_note': detection.note,
        if (payload.isNotEmpty) 'review_context': payload,
      },
      mimeType: contentType,
      sourceHint: sourceHint,
    );
    final excerpt = await buildRawTextExcerpt(bytes, detection);
    await persistRawExtractionLayer(
      importId: id,
      bytes: bytes,
      detection: detection,
      parse: null,
      rawTextExcerpt: excerpt,
    );
    if (excerpt != null && excerpt.length > 200) {
      unawaited(StatementClassificationService.classifyImport(importId: id, textExcerpt: excerpt));
    }
    await insertImportReview(
      importId: id,
      reviewType: reviewType,
      payload: {
        'file_name': fileName,
        'source_type': statementSourceTypeToDb(detection.kind),
        ...payload,
      },
    );
    return id;
  }

  static Future<void> insertImportReview({
    String? importId,
    required String reviewType,
    Map<String, dynamic> payload = const {},
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('statement_import_reviews').insert({
      'user_id': uid,
      if (importId != null) 'import_id': importId,
      'review_type': reviewType,
      'payload': payload,
    });
  }

  static Future<List<Map<String, dynamic>>> fetchImportReviews({bool unresolvedOnly = false, int limit = 100}) async {
    final uid = _uid;
    if (uid == null) return [];
    var q = _c.from('statement_import_reviews').select().eq('user_id', uid);
    if (unresolvedOnly) {
      q = q.eq('resolved', false);
    }
    final res = await q.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> setImportReviewResolved(String reviewId, {required bool resolved}) async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('statement_import_reviews').update({'resolved': resolved}).eq('id', reviewId).eq('user_id', uid);
  }

  static Future<Map<String, dynamic>?> fetchTransactionById(String id) async {
    final uid = _uid;
    if (uid == null) return null;
    return _c.from('statement_transactions').select().eq('id', id).eq('user_id', uid).maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> fetchLinksForStatementTransaction(String statementTransactionId) async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _c
        .from('statement_document_links')
        .select()
        .eq('user_id', uid)
        .eq('statement_transaction_id', statementTransactionId);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<List<Map<String, dynamic>>> fetchCategoriesForPicker() async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _c.from('categories').select('id,name').or('user_id.is.null,user_id.eq.$uid').order('name');
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Active statement debits with txn_date in [fromInclusive, toInclusive] (date-only).
  static Future<List<Map<String, dynamic>>> fetchDebitTransactionsInDateRange({
    required DateTime fromInclusive,
    required DateTime toInclusive,
    int limit = 2000,
  }) async {
    final uid = _uid;
    if (uid == null) return [];
    final from = _ymd(fromInclusive);
    final to = _ymd(toInclusive);
    final res = await _c
        .from('statement_transactions')
        .select('txn_date,amount,description_raw')
        .eq('user_id', uid)
        .eq('direction', 'debit')
        .eq('status', 'active')
        .gte('txn_date', from)
        .lte('txn_date', to)
        .order('txn_date', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Persists editable statement row fields (category may be null to clear).
  static Future<void> updateStatementTransaction(
    String id, {
    required String txnType,
    required String status,
    required String? categoryId,
    required String descriptionClean,
    required String notes,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final cur = await fetchTransactionById(id);
    final meta = Map<String, dynamic>.from((cur?['metadata'] as Map?) ?? {});
    if (notes.trim().isEmpty) {
      meta.remove('notes');
    } else {
      meta['notes'] = notes.trim();
    }
    await _c.from('statement_transactions').update({
      'txn_type': txnType,
      'status': status,
      'category_id': categoryId,
      'description_clean': descriptionClean.trim().isEmpty ? null : descriptionClean.trim(),
      'metadata': meta,
    }).eq('id', id).eq('user_id', uid);
  }

  static Future<void> insertRawRows(String importId, List<Map<String, dynamic>> payloads) async {
    final uid = _uid;
    if (uid == null) return;
    if (payloads.isEmpty) return;
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < payloads.length; i++) {
      rows.add({
        'import_id': importId,
        'user_id': uid,
        'row_index': i,
        'raw_payload': payloads[i],
      });
    }
    await _c.from('statement_transactions_raw').insert(rows);
  }

  static Future<String> upsertStatementAccount({
    required String accountName,
    required String accountType,
    String? institutionName,
    String? mask,
    String currency = 'INR',
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final existing = await _c
        .from('statement_accounts')
        .select('id')
        .eq('user_id', uid)
        .eq('account_name', accountName)
        .maybeSingle();
    if (existing != null) {
      final id = existing['id'] as String;
      await _c.from('statement_accounts').update({
        'last_seen_at': DateTime.now().toIso8601String(),
        if (mask != null) 'account_mask': mask,
        if (institutionName != null) 'institution_name': institutionName,
      }).eq('id', id);
      return id;
    }
    final row = await _c.from('statement_accounts').insert({
      'user_id': uid,
      'account_name': accountName,
      'account_type': accountType,
      'institution_name': institutionName,
      'account_mask': mask,
      'currency': currency,
      'first_seen_at': DateTime.now().toIso8601String(),
      'last_seen_at': DateTime.now().toIso8601String(),
    }).select('id').single();
    return row['id'] as String;
  }

  /// Commits normalized rows: inserts [statement_transactions], optional dedupe + canonical rows.
  static Future<StatementCommitResult> commitParsedTransactions({
    required String importId,
    required String importMode,
    required List<ParsedStatementTxn> rows,
    required String currency,
    String accountName = 'Imported account',
    String accountType = 'bank',
    String? institutionHint,
    String? accountMask,
    double? parseConfidenceReported,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    final accountId = await upsertStatementAccount(
      accountName: accountName,
      accountType: accountType,
      institutionName: institutionHint,
      mask: accountMask,
      currency: currency,
    );

    final docs = await SupabaseService.fetchDocuments();
    final savedDocs = docs.where((d) => (d['status'] as String?) != 'draft').toList();

    var imported = 0;
    var skippedDup = 0;
    var linked = 0;
    var review = 0;
    final fingerprints = <String>{};

    // One HTTP round-trip per row breaks on mobile Safari (Load failed) for large imports.
    final pendingRows = <ParsedStatementTxn>[];
    final pendingPayloads = <Map<String, dynamic>>[];
    for (final r in rows) {
      final fp = _fingerprint(uid, accountId, r.txnDate, r.amount, r.description);
      if (fingerprints.contains(fp)) {
        skippedDup++;
        continue;
      }
      fingerprints.add(fp);
      pendingRows.add(r);
      final signed = r.direction == 'debit' ? -r.amount : r.amount;
      pendingPayloads.add({
        'import_id': importId,
        'account_id': accountId,
        'user_id': uid,
        'txn_date': _ymd(r.txnDate),
        'description_raw': r.description,
        'amount': r.amount,
        'direction': r.direction,
        'signed_amount': signed,
        if (r.balance != null) 'balance': r.balance,
        'currency': currency,
        if (r.reference != null && r.reference!.isNotEmpty) 'reference_no': r.reference,
        'unique_fingerprint': fp,
        'status': 'active',
        'txn_type': 'other',
      });
    }

    // Small chunks + retries for mobile WebKit; keep_separate skips ?select=id to trim work per request.
    const txnChunkSize = 30;
    final txnIds = <String>[];

    if (importMode == 'keep_separate') {
      for (var i = 0; i < pendingPayloads.length; i += txnChunkSize) {
        final end = i + txnChunkSize > pendingPayloads.length ? pendingPayloads.length : i + txnChunkSize;
        final chunk = pendingPayloads.sublist(i, end);
        await _retryImportNetwork(() async {
          await _c.from('statement_transactions').insert(chunk);
        });
      }
      imported = pendingPayloads.length;
    } else {
      for (var i = 0; i < pendingPayloads.length; i += txnChunkSize) {
        final end = i + txnChunkSize > pendingPayloads.length ? pendingPayloads.length : i + txnChunkSize;
        final chunk = pendingPayloads.sublist(i, end);
        final res = await _retryImportNetwork(() async {
          final r = await _c.from('statement_transactions').insert(chunk).select('id');
          return r;
        });
        final inserted = List<Map<String, dynamic>>.from(res as List);
        if (inserted.length != chunk.length) {
          throw StateError('Batch insert size mismatch (${inserted.length} vs ${chunk.length}).');
        }
        for (final row in inserted) {
          txnIds.add(row['id'] as String);
        }
      }
      imported = txnIds.length;
    }

    if (importMode != 'keep_separate') {
      for (var idx = 0; idx < pendingRows.length; idx++) {
        final r = pendingRows[idx];
        final txnId = txnIds[idx];
        final signed = r.direction == 'debit' ? -r.amount : r.amount;

        Map<String, dynamic>? bestDoc;
        var bestScore = 0.0;
        for (final d in savedDocs) {
          if (d['exclude_from_goat_smart_analytics'] == true) continue;
          final s = StatementDedupe.scoreDocumentMatch(
            document: d,
            stmtDate: r.txnDate,
            stmtAmount: r.amount,
            stmtDescription: r.description,
          );
          if (s > bestScore) {
            bestScore = s;
            bestDoc = d;
          }
        }

        final mt = StatementDedupe.matchTypeForScore(bestScore);
        if (bestDoc != null && mt != 'none') {
          final exclude = bestScore >= StatementDedupe.thresholdPossible;
          await _c.from('statement_document_links').insert({
            'user_id': uid,
            'statement_transaction_id': txnId,
            'document_id': bestDoc['id'],
            'match_type': mt,
            'score': bestScore,
            'is_excluded_from_double_count': exclude,
          });
          linked++;
          if (bestScore < StatementDedupe.thresholdHigh) review++;

          if (exclude) {
            await SupabaseService.updateDocument(
              id: bestDoc['id'] as String,
              excludeFromGoatSmartAnalytics: true,
            );
          }

          await _c.from('canonical_financial_events').insert({
            'user_id': uid,
            'primary_source': 'statement',
            'primary_statement_transaction_id': txnId,
            'primary_document_id': bestDoc['id'],
            'event_date': _ymd(r.txnDate),
            'merchant_name': r.description,
            'amount': r.amount,
            'signed_amount': signed,
            'direction': r.direction,
            'currency': currency,
            'account_id': accountId,
            'dedupe_status': bestScore >= StatementDedupe.thresholdHigh ? 'resolved' : 'needs_review',
          });
        } else {
          await _c.from('canonical_financial_events').insert({
            'user_id': uid,
            'primary_source': 'statement',
            'primary_statement_transaction_id': txnId,
            'event_date': _ymd(r.txnDate),
            'merchant_name': r.description,
            'amount': r.amount,
            'signed_amount': signed,
            'direction': r.direction,
            'currency': currency,
            'account_id': accountId,
          });
        }
      }
    }

    await updateImport(
      importId,
      importStatus: 'imported',
      transactionCount: imported,
      importMode: importMode,
      parseConfidence: parseConfidenceReported ?? (rows.isEmpty ? 0 : 72),
    );

    if (review > 0) {
      await insertImportReview(
        importId: importId,
        reviewType: 'dedupe_needs_review',
        payload: {'links_needing_review': review},
      );
    }

    return StatementCommitResult(
      imported: imported,
      skippedDuplicates: skippedDup,
      linkedDocuments: linked,
      needsReview: review,
    );
  }

  static String _fingerprint(String uid, String accountId, DateTime d, double amt, String desc) {
    final norm = desc.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final raw = '$uid|$accountId|${_ymd(d)}|${amt.toStringAsFixed(2)}|$norm';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  static Future<List<Map<String, dynamic>>> fetchImports({int limit = 100}) async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _c.from('statement_imports').select().eq('user_id', uid).order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<List<Map<String, dynamic>>> fetchTransactions({int limit = 200}) async {
    final uid = _uid;
    if (uid == null) return [];
    final res =
        await _c.from('statement_transactions').select().eq('user_id', uid).order('txn_date', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<List<Map<String, dynamic>>> fetchAccounts() async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _c.from('statement_accounts').select().eq('user_id', uid).order('last_seen_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<List<Map<String, dynamic>>> fetchDocumentLinks({int limit = 200}) async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _c.from('statement_document_links').select().eq('user_id', uid).order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<List<Map<String, dynamic>>> fetchCanonicalEvents({int limit = 500}) async {
    final uid = _uid;
    if (uid == null) return [];
    final res =
        await _c.from('canonical_financial_events').select().eq('user_id', uid).order('event_date', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> deleteImport(String importId) async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('statement_imports').delete().eq('id', importId).eq('user_id', uid);
  }

  static String newImportId() => const Uuid().v4();
}

class StatementCommitResult {
  const StatementCommitResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.linkedDocuments,
    required this.needsReview,
  });

  final int imported;
  final int skippedDuplicates;
  final int linkedDocuments;
  final int needsReview;
}
