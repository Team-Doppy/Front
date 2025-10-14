import 'package:shared_preferences/shared_preferences.dart';

class FontPrefsService {
  static const String _keyCurrentFamily = 'editor.current_font_family';
  static const String _keyCurrentWeight = 'editor.current_font_weight';
  static const String _keyFavorites = 'editor.favorite_fonts';

  Future<void> saveCurrentFont(String? family, int weight) async {
    final prefs = await SharedPreferences.getInstance();
    if (family == null || family.isEmpty) {
      await prefs.remove(_keyCurrentFamily);
    } else {
      await prefs.setString(_keyCurrentFamily, family);
    }
    await prefs.setInt(_keyCurrentWeight, weight);
  }

  Future<(String?, int?)> loadCurrentFont() async {
    final prefs = await SharedPreferences.getInstance();
    final family = prefs.getString(_keyCurrentFamily);
    final weight = prefs.getInt(_keyCurrentWeight);
    return (family, weight);
  }

  Future<List<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyFavorites) ?? const [];
  }

  Future<void> toggleFavorite(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyFavorites) ?? <String>[];
    if (list.contains(family)) {
      list.removeWhere((e) => e == family);
    } else {
      list.add(family);
    }
    await prefs.setStringList(_keyFavorites, list);
  }

  Future<bool> isFavorite(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyFavorites) ?? const [];
    return list.contains(family);
  }
}
