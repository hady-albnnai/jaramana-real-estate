import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/browse_tracker.dart';

void main() {
  test('counts two distinct settled visible offers only once', () {
    final tracker = BrowseTracker();

    expect(tracker.recordVisible('offer-1', isVisible: true, scrollSettled: true), isTrue);
    expect(tracker.recordVisible('offer-1', isVisible: true, scrollSettled: true), isFalse);
    expect(tracker.recordVisible('offer-2', isVisible: false, scrollSettled: true), isFalse);
    expect(tracker.recordVisible('offer-2', isVisible: true, scrollSettled: false), isFalse);
    expect(tracker.hasTwoDistinctOffers, isFalse);

    expect(tracker.recordVisible('offer-2', isVisible: true, scrollSettled: true), isTrue);
    expect(tracker.hasTwoDistinctOffers, isTrue);
    expect(tracker.completed, isTrue);
    expect(tracker.distinctCount, 2);
  });

  test('ignores empty IDs and prevents counting after completion', () {
    final tracker = BrowseTracker();

    expect(tracker.recordVisible('', isVisible: true, scrollSettled: true), isFalse);
    tracker.recordVisible('a', isVisible: true, scrollSettled: true);
    tracker.recordVisible('b', isVisible: true, scrollSettled: true);
    expect(tracker.recordVisible('c', isVisible: true, scrollSettled: true), isFalse);
    expect(tracker.seenOfferIds, {'a', 'b'});
  });

  test('list generations do not reset distinct IDs', () {
    final tracker = BrowseTracker();
    tracker.beginListGeneration();
    tracker.recordVisible('a', isVisible: true, scrollSettled: true);
    tracker.beginListGeneration();
    tracker.recordVisible('b', isVisible: true, scrollSettled: true);

    expect(tracker.listGeneration, 2);
    expect(tracker.distinctCount, 2);
  });
}
