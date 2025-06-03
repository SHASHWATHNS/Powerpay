import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/services/numlook_service.dart';

final numlookupProvider = FutureProvider.family<String?, String>((ref, phoneNumber) async {
  final service = NumlookupService();
  return await service.getCarrierName(phoneNumber);
});
