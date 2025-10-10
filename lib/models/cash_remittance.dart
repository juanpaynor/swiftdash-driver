enum PaymentMethod {
  cash,
  card;

  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash on Delivery';
      case PaymentMethod.card:
        return 'Card Payment';
    }
  }

  String get shortName {
    switch (this) {
      case PaymentMethod.cash:
        return 'COD';
      case PaymentMethod.card:
        return 'Card';
    }
  }

  bool get requiresRemittance => this == PaymentMethod.cash;
}

enum RemittanceStatus {
  pending,
  processing,
  completed,
  failed,
  overdue;

  String get displayName {
    switch (this) {
      case RemittanceStatus.pending:
        return 'Pending';
      case RemittanceStatus.processing:
        return 'Processing';
      case RemittanceStatus.completed:
        return 'Completed';
      case RemittanceStatus.failed:
        return 'Failed';
      case RemittanceStatus.overdue:
        return 'Overdue';
    }
  }
}

class CashRemittance {
  final String id;
  final String driverId;
  final double amount;
  final RemittanceStatus status;
  final DateTime createdAt;
  final DateTime? processedAt;
  final DateTime? completedAt;
  final String? payMayaTransactionId;
  final String? failureReason;
  final List<String> earningsIds; // List of driver_earnings IDs included in this remittance

  CashRemittance({
    required this.id,
    required this.driverId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.processedAt,
    this.completedAt,
    this.payMayaTransactionId,
    this.failureReason,
    required this.earningsIds,
  });

  // Check if this remittance is overdue (more than 24 hours old and still pending)
  bool get isOverdue {
    if (status != RemittanceStatus.pending) return false;
    final hoursSinceCreated = DateTime.now().difference(createdAt).inHours;
    return hoursSinceCreated > 24;
  }

  // Hours since remittance was requested
  int get hoursSinceCreated => DateTime.now().difference(createdAt).inHours;

  factory CashRemittance.fromJson(Map<String, dynamic> json) {
    return CashRemittance(
      id: json['id'],
      driverId: json['driver_id'],
      amount: (json['amount'] as num).toDouble(),
      status: RemittanceStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
      ),
      createdAt: DateTime.parse(json['created_at']),
      processedAt: json['processed_at'] != null ? DateTime.parse(json['processed_at']) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      payMayaTransactionId: json['paymaya_transaction_id'],
      failureReason: json['failure_reason'],
      earningsIds: List<String>.from(json['earnings_ids'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'amount': amount,
      'status': status.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'processed_at': processedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'paymaya_transaction_id': payMayaTransactionId,
      'failure_reason': failureReason,
      'earnings_ids': earningsIds,
    };
  }
}