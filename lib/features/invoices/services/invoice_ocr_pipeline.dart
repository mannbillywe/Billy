import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logging/billy_logger.dart';
import '../../scanner/models/extracted_receipt.dart';

/// Upload → `invoices` row → Edge Function `process-invoice` → structured DB → [ExtractedReceipt].
class InvoiceOcrPipeline {
  InvoiceOcrPipeline._();

  static const _bucket = 'invoice-files';
  static const _uuid = Uuid();

  static String _sanitizeFileName(String name) {
    var s = name.replaceAll(RegExp(r'[\\/]+'), '_').trim();
    if (s.isEmpty) s = 'invoice';
    if (s.length > 200) s = s.substring(s.length - 200);
    return s;
  }

  static Future<({String invoiceId, ExtractedReceipt receipt})> uploadAndProcess({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String source,
  }) async {
    if (bytes.isEmpty) throw StateError('Empty file');
    if (bytes.length > 16 * 1024 * 1024) {
      throw StateError('File too large (max 16 MB)');
    }

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    final invoiceId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final safeName = _sanitizeFileName(fileName);
    final path = '$uid/$y/$m/$invoiceId/$safeName';

    BillyLogger.info(
      'invoice-ocr: upload $path (${bytes.length} bytes) → invoke process-invoice',
    );

    await client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );

    await client.from('invoices').insert({
      'id': invoiceId,
      'user_id': uid,
      'file_path': path,
      'file_name': safeName,
      'mime_type': mimeType,
      'status': 'uploaded',
      'source': source,
    });

    FunctionResponse res;
    try {
      res = await client.functions.invoke(
        'process-invoice',
        body: {
          'invoice_id': invoiceId,
          'file_path': path,
        },
      );
    } on FunctionException catch (e) {
      final msg = _formatFunctionError(e);
      BillyLogger.warn('process-invoice failed', msg);
      throw Exception(msg);
    }

    if (res.status < 200 || res.status >= 300) {
      throw Exception('OCR failed (${res.status})');
    }

    final data = res.data;
    if (data is! Map) {
      throw Exception('Invalid OCR response');
    }

    final map = Map<String, dynamic>.from(data);

    if (res.status == 202 || map['pending'] == true) {
      BillyLogger.info('invoice-ocr: accepted (async), polling $invoiceId');
      await _waitForInvoiceOcr(client, invoiceId);
      final out = await _receiptFromDb(client, invoiceId);
      BillyLogger.info('invoice-ocr: completed $invoiceId');
      return out;
    }

    if (map['success'] != true) {
      final err = map['error'];
      if (err is Map && err['message'] != null) {
        throw Exception(err['message'].toString());
      }
      throw Exception('OCR was not successful');
    }

    final inv = map['invoice'];
    final items = map['items'];
    if (inv is! Map) {
      throw Exception('Missing invoice in response');
    }

    final receipt = ExtractedReceipt.fromInvoiceOcr(
      Map<String, dynamic>.from(inv),
      items is List ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList() : const [],
    );

    BillyLogger.info('invoice-ocr: completed $invoiceId');
    return (invoiceId: invoiceId, receipt: receipt);
  }

  static Future<void> _waitForInvoiceOcr(SupabaseClient client, String invoiceId) async {
    const maxWait = Duration(seconds: 180);
    const step = Duration(milliseconds: 750);
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      final row = await client
          .from('invoices')
          .select('status,processing_error')
          .eq('id', invoiceId)
          .maybeSingle();
      final s = row?['status'] as String?;
      if (s == 'completed') return;
      if (s == 'failed') {
        final err = row?['processing_error']?.toString();
        throw Exception(err != null && err.isNotEmpty ? err : 'OCR failed');
      }
      await Future<void>.delayed(step);
    }
    throw Exception('OCR timed out. Check your connection and try again.');
  }

  static Future<({String invoiceId, ExtractedReceipt receipt})> _receiptFromDb(
    SupabaseClient client,
    String invoiceId,
  ) async {
    final inv = await client.from('invoices').select().eq('id', invoiceId).single();
    final itemsRes = await client.from('invoice_items').select().eq('invoice_id', invoiceId);
    final itemsList = (itemsRes as List?) ?? const [];
    final receipt = ExtractedReceipt.fromInvoiceOcr(
      Map<String, dynamic>.from(inv as Map<dynamic, dynamic>),
      itemsList.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
    return (invoiceId: invoiceId, receipt: receipt);
  }

  static String _formatFunctionError(FunctionException e) {
    final d = e.details;
    if (d is Map) {
      if (d['error'] is Map) {
        final inner = d['error'] as Map;
        if (inner['message'] != null) return inner['message'].toString();
      }
      if (d['message'] != null) return d['message'].toString();
    }
    switch (e.status) {
      case 401:
        return 'Sign in again, then retry.';
      case 503:
        return 'No Gemini API key: set profiles.gemini_api_key for your user in Supabase, '
            'or set GEMINI_API_KEY on the process-invoice function.';
      case 502:
        return 'OCR service failed. Try again or use a clearer image/PDF.';
      default:
        return 'OCR failed (HTTP ${e.status}).';
    }
  }
}
