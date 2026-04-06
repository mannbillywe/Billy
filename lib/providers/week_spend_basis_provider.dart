import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/document_date_range.dart';

class WeekSpendBasisNotifier extends Notifier<WeekSpendBasis> {
  @override
  WeekSpendBasis build() => WeekSpendBasis.uploadDate;

  void setBasis(WeekSpendBasis basis) => state = basis;
}

final weekSpendBasisProvider = NotifierProvider<WeekSpendBasisNotifier, WeekSpendBasis>(
  WeekSpendBasisNotifier.new,
);
