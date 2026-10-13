import 'package:flutter_test/flutter_test.dart';
import 'package:jaramana_real_estate/models/user_model.dart';
import 'package:jaramana_real_estate/models/offer_model.dart';
import 'package:jaramana_real_estate/models/appointment_model.dart';

void main() {
  group('RLS Security Lockdown Resilience Test', () {
    test('UserModel parses safely when private fields (e.g. img) are stripped by RLS', () {
      final restrictedJson = {
        'id': '00000000-0000-0000-0000-000000000001',
        'ph': '0911222333',
        'nm': 'هادي البناء',
        'role': 2,
        'ts_crt': '2026-07-04T12:00:00Z',
      };

      final user = UserModel.fromSupabase(restrictedJson, '00000000-0000-0000-0000-000000000001');
      expect(user.uid, '00000000-0000-0000-0000-000000000001');
      expect(user.ph, '0911222333');
      expect(user.nm, 'هادي البناء');
      expect(user.role, 2);
      expect(user.img, '');
    });

    test('OfferModel parses safely under unauthenticated / public list queries', () {
      final publicOfferJson = {
        'id': '00000000-0000-0000-0000-000000000002',
        'usr_id': '00000000-0000-0000-0000-000000000001',
        'tp': 1,
        'cat': 1,
        'ttl': 'شقة فاخرة في جرمانا',
        'prc': 50000,
        'cur': 1,
        'sts': 2,
        'loc': {'region': 'جرمانا'},
        'imgs': ['img1.jpg'],
        'ts_crt': '2026-07-04T12:00:00Z',
      };

      final offer = OfferModel.fromSupabase(publicOfferJson, '00000000-0000-0000-0000-000000000002');
      expect(offer.id, '00000000-0000-0000-0000-000000000002');
      expect(offer.ttl, 'شقة فاخرة في جرمانا');
      expect(offer.sts, 2);
      expect(offer.loc['region'], 'جرمانا');
      expect(offer.imgs.length, 1);
    });

    test('AppointmentModel parses safely under broker restricted queries', () {
      final appointmentJson = {
        'id': '00000000-0000-0000-0000-000000000003',
        'rq_uid': '00000000-0000-0000-0000-000000000001',
        'ow_uid': '00000000-0000-0000-0000-000000000004',
        'of_id': '00000000-0000-0000-0000-000000000002',
        'dt': '2026-07-05T10:00:00Z',
        'sts': 1,
        'ts_crt': '2026-07-04T12:00:00Z',
      };

      final appt = AppointmentModel.fromSupabase(appointmentJson, '00000000-0000-0000-0000-000000000003');
      expect(appt.id, '00000000-0000-0000-0000-000000000003');
      expect(appt.sts, 1);
      expect(appt.neog, isEmpty);
    });
  });
}
