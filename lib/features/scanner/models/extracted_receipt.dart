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
    this.paymentStatus,
    this.notes,
    this.confidence = 'medium',
  });

  final String vendorName;
  final String date;
  final String? invoiceNumber;
  final List<LineItem> lineItems;
  final double subtotal;
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
  final String? paymentStatus;
  final String? notes;
  final String confidence;

  factory ExtractedReceipt.fromJson(Map<String, dynamic> json) {
    // Handle both single invoice and array of invoices
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

    return ExtractedReceipt(
      vendorName: _str(invoice['vendor_name']) ?? 'Unknown',
      date: _str(invoice['invoice_date']) ?? _str(invoice['date']) ?? '',
      invoiceNumber: _str(invoice['invoice_number']),
      lineItems: items,
      subtotal: _num(invoice['subtotal']),
      tax: _num(invoice['gst']) + _num(invoice['cgst']) + _num(invoice['sgst']) + _num(invoice['igst']) + _num(invoice['tax']),
      total: _num(invoice['total_amount']) > 0 ? _num(invoice['total_amount']) : _num(invoice['total']),
      currency: _str(invoice['currency']) ?? 'INR',
      category: _str(invoice['category']),
      paymentMethod: _str(invoice['payment_method']),
      vendorAddress: _str(invoice['vendor_address']),
      vendorPhone: _str(invoice['vendor_phone']),
      vendorGstin: _str(invoice['vendor_gstin']),
      buyerName: _str(invoice['buyer_name']),
      buyerGstin: _str(invoice['buyer_gstin']),
      cgst: _num(invoice['cgst']),
      sgst: _num(invoice['sgst']),
      igst: _num(invoice['igst']),
      paymentStatus: _str(invoice['payment_status']),
      notes: _str(invoice['notes']),
      confidence: _str(json['extraction_confidence']) ?? 'medium',
    );
  }

  Map<String, dynamic> toJson() => {
    'vendor_name': vendorName,
    'invoice_date': date,
    'invoice_number': invoiceNumber,
    'line_items': lineItems.map((e) => e.toJson()).toList(),
    'subtotal': subtotal,
    'cgst': cgst,
    'sgst': sgst,
    'igst': igst,
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
  });

  final String description;
  final int quantity;
  final double? unitPrice;
  final double total;
  final String? hsnCode;

  factory LineItem.fromJson(Map<String, dynamic> json) {
    return LineItem(
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      total: (json['amount'] as num?)?.toDouble() ?? (json['total'] as num?)?.toDouble() ?? 0,
      hsnCode: json['hsn_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'description': description,
    'quantity': quantity,
    'unit_price': unitPrice,
    'amount': total,
    'hsn_code': hsnCode,
  };
}
