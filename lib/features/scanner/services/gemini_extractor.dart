import 'dart:convert';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../../../config/gemini_config.dart';
import '../../../core/logging/billy_logger.dart';
import '../models/extracted_receipt.dart';

/// Single-shot invoice extraction: exactly ONE Gemini API call per image.
/// No retries, no model fallbacks - avoids rate limits.
class GeminiExtractor {
  GeminiExtractor({String? apiKey})
      : _model = GenerativeModel(
          model: GeminiConfig.model,
          apiKey: apiKey ?? GeminiConfig.apiKey,
        );

  final GenerativeModel _model;

  static const _prompt = '''
You are an expert invoice and bill data extractor. Analyze this image which may contain an invoice, bill, or receipt. It can be printed, handwritten, or mixed.

Extract ALL data found. Return ONLY valid JSON (no markdown, no code blocks):

{
  "invoices": [
    {
      "invoice_number": "",
      "invoice_date": "YYYY-MM-DD",
      "due_date": "",
      "vendor_name": "",
      "vendor_address": "",
      "vendor_phone": "",
      "vendor_email": "",
      "vendor_gstin": "",
      "buyer_name": "",
      "buyer_address": "",
      "buyer_gstin": "",
      "line_items": [
        {"description": "", "quantity": 1, "unit_price": 0, "amount": 0, "hsn_code": ""}
      ],
      "subtotal": 0,
      "gst": 0,
      "cgst": 0,
      "cgst_rate": 0,
      "sgst": 0,
      "sgst_rate": 0,
      "igst": 0,
      "igst_rate": 0,
      "other_taxes": 0,
      "total_amount": 0,
      "category": "",
      "payment_method": "",
      "payment_status": "",
      "notes": ""
    }
  ],
  "total_invoices_found": 1,
  "extraction_confidence": "high"
}

Category must be one of: Food & Beverage, Laundry, Room Service, Housekeeping Supplies, Kitchen Supplies, Maintenance, Vendor Supplies, Utilities, Guest Amenities, Equipment, Stationery, Transportation, Groceries, Shopping, Dining, Other.

Rules:
- Extract ALL invoices if multiple are present
- Handle handwritten text carefully
- If a field is not found, use "" for text or 0 for numbers
- Convert all amounts to numbers (remove ₹, Rs, commas)
- Look for GST/CGST/SGST/IGST breakdowns
- For taxi/auto receipts, extract route and fare
- For UPI receipts, extract transaction ID
- Return ONLY valid JSON
''';

  /// Single-shot extraction: exactly 1 API call per image. No retries.
  Future<ExtractedReceipt> extractFromImage(
    List<int> imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    BillyLogger.info('Extraction started (image size: ${imageBytes.length} bytes)');

    final content = [
      Content.multi([
        TextPart(_prompt),
        DataPart(mimeType, Uint8List.fromList(imageBytes)),
      ]),
    ];

    try {
      final response = await _model.generateContent(content);

      final text = response.text;
      if (text == null || text.isEmpty) {
        final candCount = response.candidates.length;
        BillyLogger.warn('Gemini returned empty response', 'candidates: $candCount');
        throw Exception('No response from Gemini');
      }

      BillyLogger.info('Extraction response received (${text.length} chars)');

      var jsonStr = text.trim();

      // Strip markdown code blocks
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceFirst(RegExp(r'^```\w*\n?'), '').replaceFirst(RegExp(r'\n?```$'), '');
      }

      // Try to extract JSON if there's extra text
      if (!jsonStr.startsWith('{')) {
        final match = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
        if (match != null) {
          jsonStr = match.group(0)!;
        }
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      BillyLogger.info('Extraction succeeded');
      return ExtractedReceipt.fromJson(json);
    } catch (e, stack) {
      BillyLogger.extractionFailed(e, stack);
      rethrow;
    }
  }
}
