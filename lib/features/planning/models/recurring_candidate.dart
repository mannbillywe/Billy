class RecurringCandidate {
  final String vendorPattern;
  final String suggestedCadence;
  final double avgAmount;
  final int occurrenceCount;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<String> sampleTransactionIds;
  final double confidence;

  const RecurringCandidate({
    required this.vendorPattern,
    required this.suggestedCadence,
    required this.avgAmount,
    required this.occurrenceCount,
    required this.firstSeen,
    required this.lastSeen,
    required this.sampleTransactionIds,
    required this.confidence,
  });

  Map<String, dynamic> toMap() => {
        'vendor_pattern': vendorPattern,
        'suggested_cadence': suggestedCadence,
        'avg_amount': avgAmount,
        'occurrence_count': occurrenceCount,
        'first_seen': firstSeen.toIso8601String(),
        'last_seen': lastSeen.toIso8601String(),
        'sample_transaction_ids': sampleTransactionIds,
        'confidence': confidence,
      };

  factory RecurringCandidate.fromMap(Map<String, dynamic> map) {
    return RecurringCandidate(
      vendorPattern: map['vendor_pattern'] as String,
      suggestedCadence: map['suggested_cadence'] as String,
      avgAmount: (map['avg_amount'] as num).toDouble(),
      occurrenceCount: map['occurrence_count'] as int,
      firstSeen: DateTime.parse(map['first_seen'] as String),
      lastSeen: DateTime.parse(map['last_seen'] as String),
      sampleTransactionIds:
          (map['sample_transaction_ids'] as List).cast<String>(),
      confidence: (map['confidence'] as num).toDouble(),
    );
  }

  @override
  String toString() =>
      'RecurringCandidate($vendorPattern, $suggestedCadence, '
      'avg=$avgAmount, count=$occurrenceCount, confidence=$confidence)';
}
