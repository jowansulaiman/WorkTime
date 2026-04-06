enum ComplianceSeverity { blocking, warning }

extension ComplianceSeverityX on ComplianceSeverity {
  String get value => switch (this) {
        ComplianceSeverity.blocking => 'blocking',
        ComplianceSeverity.warning => 'warning',
      };

  String get label => switch (this) {
        ComplianceSeverity.blocking => 'Blockiert',
        ComplianceSeverity.warning => 'Warnung',
      };

  static ComplianceSeverity fromValue(String? value) => switch (value) {
        'warning' => ComplianceSeverity.warning,
        _ => ComplianceSeverity.blocking,
      };
}

class ComplianceViolation {
  const ComplianceViolation({
    required this.code,
    required this.severity,
    required this.message,
    this.relatedEntityIds = const [],
  });

  final String code;
  final ComplianceSeverity severity;
  final String message;
  final List<String> relatedEntityIds;

  bool get isBlocking => severity == ComplianceSeverity.blocking;

  factory ComplianceViolation.fromMap(Map<String, dynamic> map) {
    return ComplianceViolation(
      code: (map['code'] ?? '').toString(),
      severity: ComplianceSeverityX.fromValue(map['severity']?.toString()),
      message: (map['message'] ?? '').toString(),
      relatedEntityIds:
          ((map['relatedEntityIds'] as List<dynamic>?) ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'severity': severity.value,
      'message': message,
      'relatedEntityIds': relatedEntityIds,
    };
  }
}
