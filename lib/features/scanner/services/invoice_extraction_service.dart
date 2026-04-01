import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/billy_logger.dart';
import '../models/extracted_receipt.dart';

/// Server-side extraction only: one Edge Function invocation per image (one Gemini call on server).
class InvoiceExtractionService {
  InvoiceExtractionService._();

  static Future<ExtractedReceipt> extractOnce(
    List<int> imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    if (imageBytes.isEmpty) {
      throw StateError('Empty image');
    }

    final client = Supabase.instance.client;
    BillyLogger.info('extract-invoice: invoking edge function (${imageBytes.length} bytes, $mimeType)');

    final res = await client.functions.invoke(
      'extract-invoice',
      body: {
        'image_base64': base64Encode(imageBytes),
        'mime_type': mimeType,
      },
    );

    if (res.status != 200) {
      final err = _parseError(res.data);
      BillyLogger.warn('extract-invoice failed', 'status=${res.status} $err');
      throw Exception(err ?? 'Extraction failed (${res.status})');
    }

    final data = res.data;
    if (data is! Map) {
      throw Exception('Invalid extraction response');
    }
    final raw = data['extraction'];
    if (raw is! Map) {
      throw Exception('Missing extraction payload');
    }

    final map = Map<String, dynamic>.from(raw);
    BillyLogger.info('extract-invoice: success');
    return ExtractedReceipt.fromJson(map);
  }

  static String? _parseError(dynamic data) {
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    return null;
  }
}
