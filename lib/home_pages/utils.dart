import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

String getInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.map((e) => e[0].toUpperCase()).take(2).join();
}

String formatNumber(double number) {
  final formatter = NumberFormat('#,##0.##');
  return formatter.format(number);
}

String getStatus(Map<String, dynamic> data) {
  if (data['api_response']?['data']?['attributes']?['status'] != null) {
    return data['api_response']['data']['attributes']['status']
        .toString()
        .toLowerCase();
  }
  if (data['fullData']?['attributes']?['status'] != null) {
    return data['fullData']['attributes']['status'].toString().toLowerCase();
  }
  if (data['status'] != null) {
    return data['status'].toString().toLowerCase();
  }
  return 'unknown';
}

IconData getIcon(String type, bool isOutgoing) {
  switch (type.toLowerCase()) {
    case 'transfer':
      return isOutgoing ? FontAwesomeIcons.paperPlane : Icons.arrow_downward;
    case 'airtime':
      return FontAwesomeIcons.phone;
    case 'data':
    case 'mobile_data':
      return FontAwesomeIcons.wifi;
    case 'electricity':
      return FontAwesomeIcons.bolt;
    case 'cable':
      return Icons.tv;
    case 'add_money':
    case 'fund':
      return Icons.add;
    case 'giveaway_claim':
      return FontAwesomeIcons.gift;
    case 'giveaway_create':
      return FontAwesomeIcons.gift;
    case 'ghost_transfer':
      return FontAwesomeIcons.ghost;
    case 'atm_payment':
      return FontAwesomeIcons.creditCard;
    default:
      return FontAwesomeIcons.exchangeAlt;
  }
}
