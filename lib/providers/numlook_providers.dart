import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/services/numlook_service.dart';
import '../models/number_details.dart';

final numlookupProvider =
FutureProvider.family<NumberDetails?, String>((ref, phone) async {
  return await NumlookupService().lookup(phone);
});
