import 'package:flutter_riverpod/flutter_riverpod.dart';

final navigationIndexProvider = StateProvider<int>((ref) => 0);
final lastBackPressProvider = StateProvider<DateTime?>((ref) => null);
