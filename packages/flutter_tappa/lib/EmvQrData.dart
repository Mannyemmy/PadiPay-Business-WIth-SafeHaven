class EmvQrData {
  final String amount;
  final String currency;
  final String date;
  final String tvr;
  final String amountOther;
  final String transactionType;
  final String unpredictableNo;
  final String pan;
  final String aid;
  final String aip;
  final String issuerUrl;
  final String cardHolderName;
  final String panSeqNo;
  final String track2;
  final String cryptogram;
  final String cid;
  final String iad;
  final String atc;
  final String raw;

  EmvQrData({
    required this.amount,
    required this.currency,
    required this.date,
    required this.tvr,
    required this.amountOther,
    required this.transactionType,
    required this.unpredictableNo,
    required this.pan,
    required this.aid,
    required this.aip,
    required this.issuerUrl,
    required this.cardHolderName,
    required this.panSeqNo,
    required this.track2,
    required this.cryptogram,
    required this.cid,
    required this.iad,
    required this.atc,
    required this.raw,
  });

  factory EmvQrData.fromMap(Map<dynamic, dynamic> map) {
    return EmvQrData(
      amount: map['amount'] ?? '',
      currency: map['currency'] ?? '',
      date: map['date'] ?? '',
      tvr: map['tvr'] ?? '',
      amountOther: map['amountOther'] ?? '',
      transactionType: map['transactionType'] ?? '',
      unpredictableNo: map['unpredictableNo'] ?? '',
      pan: map['pan'] ?? '',
      aid: map['aid'] ?? '',
      aip: map['aip'] ?? '',
      issuerUrl: map['issuerUrl'] ?? '',
      cardHolderName: map['cardHolderName'] ?? '',
      panSeqNo: map['panSeqNo'] ?? '',
      track2: map['track2'] ?? '',
      cryptogram: map['cryptogram'] ?? '',
      cid: map['cid'] ?? '',
      iad: map['iad'] ?? '',
      atc: map['atc'] ?? '',
      raw: map['raw'] ?? '',
    );
  }
}
