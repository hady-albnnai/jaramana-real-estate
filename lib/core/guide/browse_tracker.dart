/// Tracks distinct visitor offers that were actually visible and settled.
/// It has no dependency on OfferProvider, scrolling widgets, or navigation.
class BrowseTracker {
  final Set<String> _seenOfferIds = <String>{};
  int _listGeneration = 0;
  bool _completed = false;

  int get listGeneration => _listGeneration;
  int get distinctCount => _seenOfferIds.length;
  bool get hasTwoDistinctOffers => _seenOfferIds.length >= 2;
  bool get completed => _completed;
  Set<String> get seenOfferIds => Set.unmodifiable(_seenOfferIds);

  /// Starts a new visible-list generation. Existing IDs remain known so a
  /// refresh or pagination page cannot count the same offer twice.
  void beginListGeneration() {
    _listGeneration++;
  }

  /// Records an offer only when its card was actually visible and scrolling
  /// had settled. Loading rows, empty IDs, and in-flight gestures are ignored.
  bool recordVisible(
    String offerId, {
    required bool isVisible,
    required bool scrollSettled,
  }) {
    final id = offerId.trim();
    if (_completed || id.isEmpty || !isVisible || !scrollSettled) return false;
    final added = _seenOfferIds.add(id);
    if (hasTwoDistinctOffers) _completed = true;
    return added;
  }

  /// Clears a tracker when leaving the visitor flow or starting a new guide
  /// content version. This intentionally does not persist anything itself.
  void reset() {
    _seenOfferIds.clear();
    _completed = false;
    _listGeneration = 0;
  }
}
