class ExtractedReceipt {
  ExtractedReceipt({
    required this.vendorName,
    required this.date,
    this.invoiceNumber,
    required this.lineItems,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.currency = 'INR',
    this.category,
    this.paymentMethod,
    this.vendorAddress,
    this.vendorPhone,
    this.vendorGstin,
    this.buyerName,
    this.buyerGstin,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.discount = 0,
    this.paymentStatus,
    this.notes,
    this.confidence = 'medium',
  });

  final String vendorName;
  final String date;
  final String? invoiceNumber;
  final List<LineItem> lineItems;
  final double subtotal;
  /// Combined tax amount for legacy `documents.tax_amount` (CGST+SGST+IGST or GST field).
  final double tax;
  final double total;
  final String currency;
  final String? category;
  final String? paymentMethod;
  final String? vendorAddress;
  final String? vendorPhone;
  final String? vendorGstin;
  final String? buyerName;
  final String? buyerGstin;
  final double cgst;
  final double sgst;
  final double igst;
  final double discount;
  final String? paymentStatus;
  final String? notes;
  final String confidence;

  ExtractedReceipt copyWith({
    String? vendorName,
    String? date,
    String? invoiceNumber,
    List<LineItem>? lineItems,
    double? subtotal,
    double? tax,
    double? total,
    String? currency,
    String? category,
    String? paymentMethod,
    double? cgst,
    double? sgst,
    double? igst,
    double? discount,
    String? notes,
    String? confidence,
  }) {
    return ExtractedReceipt(
      vendorName: vendorName ?? this.vendorName,
      date: date ?? this.date,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      lineItems: lineItems ?? this.lineItems,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      vendorAddress: this.vendorAddress,
      vendorPhone: this.vendorPhone,
      vendorGstin: this.vendorGstin,
      buyerName: this.buyerName,
      buyerGstin: this.buyerGstin,
      cgst: cgst ?? this.cgst,
      sgst: sgst ?? this.sgst,
      igst: igst ?? this.igst,
      discount: discount ?? this.discount,
      paymentStatus: this.paymentStatus,
      notes: notes ?? this.notes,
      confidence: confidence ?? this.confidence,
    );
  }

  factory ExtractedReceipt.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> invoice = json;
    if (json.containsKey('invoices') && json['invoices'] is List) {
      final invoices = json['invoices'] as List;
      if (invoices.isNotEmpty) {
        invoice = invoices[0] as Map<String, dynamic>;
      }
    }

    final items = (invoice['line_items'] as List<dynamic>?)
            ?.map((e) => LineItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final cgst = _num(invoice['cgst']);
    final sgst = _num(invoice['sgst']);
    final igst = _num(invoice['igst']);
    final gstField = _num(invoice['gst']);
    final taxField = _num(invoice['tax']);
    final explicitGstParts = cgst + sgst + igst;
    // Avoid double-counting: prefer explicit CGST/SGST/IGST; else fall back to single gst/tax fields.
    final combinedTax = explicitGstParts > 0 ? explicitGstParts : (gstField + taxField);

    return ExtractedReceipt(
      vendorName: _str(invoice['vendor_name']) ?? 'Unknown',
      date: _str(invoice['invoice_date']) ?? _str(invoice['date']) ?? '',
      invoiceNumber: _str(invoice['invoice_number']),
      lineItems: items,
      subtotal: _num(invoice['subtotal']),
      tax: combinedTax,
      total: _num(invoice['total_amount']) > 0 ? _num(invoice['total_amount']) : _num(invoice['total']),
      currency: _str(invoice['currency']) ?? 'INR',
      category: _str(invoice['category']),
      paymentMethod: _str(invoice['payment_method']),
      vendorAddress: _str(invoice['vendor_address']),
      vendorPhone: _str(invoice['vendor_phone']),
      vendorGstin: _str(invoice['vendor_gstin']),
      buyerName: _str(invoice['buyer_name']),
      buyerGstin: _str(invoice['buyer_gstin']),
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      discount: _num(invoice['discount']),
      paymentStatus: _str(invoice['payment_status']),
      notes: _str(invoice['notes']),
      confidence: _str(json['extraction_confidence']) ?? 'medium',
    );
  }

  /// From `process-invoice` Edge Function (`invoices` + `invoice_items` rows).
  factory ExtractedReceipt.fromInvoiceOcr(
    Map<String, dynamic> inv,
    List<Map<String, dynamic>> items,
  ) {
    String dateStr = '';
    final idate = inv['invoice_date'];
    if (idate != null) {
      dateStr = idate.toString().split('T').first;
    }
    if (dateStr.isEmpty) {
      dateStr = DateTime.now().toIso8601String().split('T').first;
    }

    final lineItems = items.map((row) {
      final qtyNum = (row['quantity'] as num?)?.toDouble() ?? 1;
      var q = qtyNum.round();
      if (q < 1) q = 1;
      if (q > 999999) q = 999999;
      var lineCat = row['category'] as String?;
      if (lineCat == null || lineCat.trim().isEmpty) lineCat = 'Uncategorized';
      return LineItem(
        description: row['description'] as String? ?? '',
        quantity: q,
        unitPrice: (row['unit_price'] as num?)?.toDouble(),
        total: (row['amount'] as num?)?.toDouble() ?? 0,
        hsnCode: row['item_code'] as String?,
        category: lineCat,
        taxPercent: (row['tax_percent'] as num?)?.toDouble(),
        taxAmount: (row['tax_amount'] as num?)?.toDouble(),
      );
    }).toList();

    var cgst = (inv['cgst'] as num?)?.toDouble() ?? 0;
    var sgst = (inv['sgst'] as num?)?.toDouble() ?? 0;
    final igst = (inv['igst'] as num?)?.toDouble() ?? 0;
    final totalTaxField = (inv['total_tax'] as num?)?.toDouble() ?? 0;
    var explicit = cgst + sgst + igst;
    // DB may only have total_tax when OCR put everything in `gst` (pre-split invoices).
    if (explicit <= 0 && totalTaxField > 0 && igst <= 0) {
      cgst = double.parse((totalTaxField / 2).toStringAsFixed(2));
      sgst = double.parse((totalTaxField - cgst).toStringAsFixed(2));
      explicit = cgst + sgst + igst;
    }
    final combinedTax = explicit > 0 ? explicit : totalTaxField;

    final conf = inv['confidence'];
    var confidence = 'medium';
    if (conf is num) {
      if (conf >= 0.85) confidence = 'high';
      if (conf < 0.5) confidence = 'low';
    }

    final vendor = (inv['vendor_name'] as String?)?.trim();
    final expenseCat = (inv['expense_category'] as String?)?.trim();
    String? headerCategory = expenseCat != null && expenseCat.isNotEmpty ? expenseCat : null;
    if (headerCategory == null && lineItems.isNotEmpty) {
      final weights = <String, double>{};
      for (final li in lineItems) {
        final c = li.category ?? '';
        if (c.isEmpty || c == 'Uncategorized') continue;
        weights[c] = (weights[c] ?? 0) + li.total;
      }
      if (weights.isNotEmpty) {
        MapEntry<String, double>? best;
        for (final e in weights.entries) {
          if (best == null || e.value > best.value) best = e;
        }
        headerCategory = best?.key;
      }
    }
    if (headerCategory == null && lineItems.isNotEmpty) {
      headerCategory = lineItems.first.category ?? 'Uncategorized';
    }

    return ExtractedReceipt(
      vendorName: (vendor != null && vendor.isNotEmpty) ? vendor : 'Unknown',
      date: dateStr,
      invoiceNumber: inv['invoice_number'] as String?,
      lineItems: lineItems,
      subtotal: (inv['subtotal'] as num?)?.toDouble() ?? 0,
      tax: combinedTax,
      total: (inv['total'] as num?)?.toDouble() ?? 0,
      currency: inv['currency'] as String? ?? 'INR',
      category: headerCategory,
      paymentMethod: null,
      vendorGstin: inv['vendor_gstin'] as String?,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      discount: (inv['discount'] as num?)?.toDouble() ?? 0,
      paymentStatus: inv['payment_status'] as String?,
      notes: null,
      confidence: confidence,
    );
  }

  Map<String, dynamic> toJson() => {
        'vendor_name': vendorName,
        'invoice_date': date,
        'invoice_number': invoiceNumber,
        'line_items': lineItems.map((e) => e.toJson()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'tax_combined': tax,
        'total_amount': total,
        'currency': currency,
        'category': category,
        'payment_method': paymentMethod,
        'vendor_address': vendorAddress,
        'vendor_phone': vendorPhone,
        'vendor_gstin': vendorGstin,
        'buyer_name': buyerName,
        'buyer_gstin': buyerGstin,
        'payment_status': paymentStatus,
        'notes': notes,
        'extraction_confidence': confidence,
      };

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(RegExp(r'[₹Rs,\s]'), '').trim();
    return double.tryParse(s) ?? 0;
  }
}

class LineItem {
  LineItem({
    required this.description,
    this.quantity = 1,
    this.unitPrice,
    required this.total,
    this.hsnCode,
    this.category,
    this.taxPercent,
    this.taxAmount,
  });

  final String description;
  final int quantity;
  final double? unitPrice;
  final double total;
  final String? hsnCode;
  final String? category;
  final double? taxPercent;
  final double? taxAmount;

  LineItem copyWith({
    String? description,
    int? quantity,
    double? unitPrice,
    double? total,
    String? hsnCode,
    String? category,
    double? taxPercent,
    double? taxAmount,
  }) {
    return LineItem(
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      total: total ?? this.total,
      hsnCode: hsnCode ?? this.hsnCode,
      category: category ?? this.category,
      taxPercent: taxPercent ?? this.taxPercent,
      taxAmount: taxAmount ?? this.taxAmount,
    );
  }

  factory LineItem.fromJson(Map<String, dynamic> json) {
    return LineItem(
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      total: (json['amount'] as num?)?.toDouble() ?? (json['total'] as num?)?.toDouble() ?? 0,
      hsnCode: json['hsn_code'] as String?,
      category: json['category'] as String?,
      taxPercent: (json['tax_percent'] as num?)?.toDouble(),
      taxAmount: (json['tax_amount'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'amount': total,
        'hsn_code': hsnCode,
        'category': category,
        'tax_percent': taxPercent,
        'tax_amount': taxAmount,
      };
}
