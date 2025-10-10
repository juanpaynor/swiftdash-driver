class CashBalance {
  final String id;
  final String driverId;
  final double currentBalance;
  final double pendingRemittance;
  final DateTime lastRemittanceDate;
  final DateTime nextRemittanceDue;
  final DateTime updatedAt;

  CashBalance({
    required this.id,
    required this.driverId,
    required this.currentBalance,
    required this.pendingRemittance,
    required this.lastRemittanceDate,
    required this.nextRemittanceDue,
    required this.updatedAt,
  });

  // Check if remittance is overdue
  bool get isRemittanceOverdue => DateTime.now().isAfter(nextRemittanceDue);
  
  // Hours until remittance is due
  int get hoursUntilDue {
    final now = DateTime.now();
    if (now.isAfter(nextRemittanceDue)) return 0;
    return nextRemittanceDue.difference(now).inHours;
  }

  // Minutes until remittance is due (for countdown)
  int get minutesUntilDue {
    final now = DateTime.now();
    if (now.isAfter(nextRemittanceDue)) return 0;
    return nextRemittanceDue.difference(now).inMinutes;
  }

  factory CashBalance.fromJson(Map<String, dynamic> json) {
    return CashBalance(
      id: json['id'],
      driverId: json['driver_id'],
      currentBalance: (json['current_balance'] as num).toDouble(),
      pendingRemittance: (json['pending_remittance'] as num).toDouble(),
      lastRemittanceDate: DateTime.parse(json['last_remittance_date']),
      nextRemittanceDue: DateTime.parse(json['next_remittance_due']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'current_balance': currentBalance,
      'pending_remittance': pendingRemittance,
      'last_remittance_date': lastRemittanceDate.toIso8601String(),
      'next_remittance_due': nextRemittanceDue.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}