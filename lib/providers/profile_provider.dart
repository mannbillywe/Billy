import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) => SupabaseService.fetchProfile());
