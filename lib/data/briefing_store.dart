import 'package:shared_preferences/shared_preferences.dart';

abstract class BriefingStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

class PreferencesStore implements BriefingStore {
  PreferencesStore(this.preferences);
  final SharedPreferences preferences;
  @override
  String? read(String key) => preferences.getString(key);
  @override
  Future<void> write(String key, String value) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Storage unavailable');
    }
  }
}

class MemoryStore implements BriefingStore {
  final Map<String, String> values = {};
  @override
  String? read(String key) => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
