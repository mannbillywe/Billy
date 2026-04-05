import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

class DocumentsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => SupabaseService.fetchDocuments();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => SupabaseService.fetchDocuments());
  }

  /// Returns the new document id, or null if not signed in / insert skipped.
  Future<String?> addDocument({
    required String vendorName,
    required double amount,
    required double taxAmount,
    required String date,
    String type = 'receipt',
    String? description,
    String? paymentMethod,
    String? currency,
    Map<String, dynamic>? extractedData,
    String status = 'saved',
    String? categoryId,
    String? categorySource,
  }) async {
    final id = await SupabaseService.insertDocument(
      vendorName: vendorName,
      amount: amount,
      taxAmount: taxAmount,
      date: date,
      type: type,
      description: description,
      paymentMethod: paymentMethod,
      currency: currency,
      extractedData: extractedData,
      status: status,
      categoryId: categoryId,
      categorySource: categorySource,
    );
    await refresh();
    return id;
  }

  Future<void> deleteDoc(String id) async {
    await SupabaseService.deleteDocument(id);
    await refresh();
  }

  Future<void> updateDocument({
    required String id,
    String? vendorName,
    double? amount,
    double? taxAmount,
    String? date,
    String? type,
    String? description,
    String? paymentMethod,
    String? currency,
    Map<String, dynamic>? extractedData,
    String? status,
    String? categoryId,
    String? categorySource,
    bool writeCategorySource = false,
  }) async {
    await SupabaseService.updateDocument(
      id: id,
      vendorName: vendorName,
      amount: amount,
      taxAmount: taxAmount,
      date: date,
      type: type,
      description: description,
      paymentMethod: paymentMethod,
      currency: currency,
      extractedData: extractedData,
      status: status,
      categoryId: categoryId,
      categorySource: categorySource,
      writeCategorySource: writeCategorySource,
    );
    await refresh();
  }

  Future<void> syncDocumentFromLinkedInvoice(String documentId) async {
    await SupabaseService.syncDocumentFromLinkedInvoice(documentId);
    await refresh();
  }
}

final documentsProvider =
    AsyncNotifierProvider<DocumentsNotifier, List<Map<String, dynamic>>>(DocumentsNotifier.new);
