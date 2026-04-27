class LoyaltyCardResult {
  final bool success;
  final String? data;
  final int? errorCode;
  final String? errorMessage;

  LoyaltyCardResult({
    required this.success,
    this.data,
    this.errorCode,
    this.errorMessage,
  });

  factory LoyaltyCardResult.fromMap(dynamic map) {
    if (map is Map) {
      final success = map['success'] as bool;
      return LoyaltyCardResult(
        success: success,
        data: success ? map['data'] as String? : null,
        errorCode: !success ? map['errorCode'] as int? : null,
        errorMessage: !success ? map['errorMessage'] as String? : null,
      );
    }
    return LoyaltyCardResult(success: false, errorMessage: 'Invalid response format');
  }
}