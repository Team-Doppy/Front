import 'package:flutter/foundation.dart';
import 'package:doppy/data/models/post_data.dart';

class SearchProvider extends ChangeNotifier {
  List<PostData> _searchResults = [];
  String _searchQuery = '';
  bool _hasSearchResults = false;
  bool _isSearchOverlayVisible = false;

  List<PostData> get searchResults => _searchResults;
  String get searchQuery => _searchQuery;
  bool get hasSearchResults => _hasSearchResults;
  bool get isSearchOverlayVisible => _isSearchOverlayVisible;

  // 검색 중이거나 오버레이가 열려있으면 true
  bool get isSearchActive => _hasSearchResults || _isSearchOverlayVisible;

  void setSearchResults(List<PostData> results, String query) {
    _searchResults = results;
    _searchQuery = query;
    _hasSearchResults = true;
    notifyListeners();
  }

  void clearSearchResults() {
    _searchResults = [];
    _searchQuery = '';
    _hasSearchResults = false;
    notifyListeners();
  }

  void setSearchOverlayVisible(bool visible) {
    _isSearchOverlayVisible = visible;
    notifyListeners();
  }
}
