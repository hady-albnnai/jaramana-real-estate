
class LawyerProfileModel {
  final String uid;
  final String fullName;
  final String phone;
  final String whatsappPhone;
  final String officeAddress;
  final String specialization;
  final Map<String, List<String>> avl;
  final int activeTasksCount;

  const LawyerProfileModel({
    required this.uid,
    required this.fullName,
    required this.phone,
    required this.whatsappPhone,
    required this.officeAddress,
    required this.specialization,
    required this.avl,
    required this.activeTasksCount,
  });

  factory LawyerProfileModel.fromMap(Map<String, dynamic> map) {
    Map<String, List<String>> parsedAvl = {};
    final rawAvl = map['avl'];
    if (rawAvl is Map) {
      rawAvl.forEach((k, v) {
        if (v is List) {
          parsedAvl[k.toString()] = v.map((e) => e.toString()).toList();
        }
      });
    }

    return LawyerProfileModel(
      uid: (map['uid'] ?? map['id'] ?? '').toString(),
      fullName: (map['nm'] ?? map['full_name'] ?? '').toString(),
      phone: (map['ph'] ?? map['phone'] ?? '').toString(),
      whatsappPhone: (map['whatsapp_phone'] ?? '').toString(),
      officeAddress: (map['office_address'] ?? '').toString(),
      specialization: (map['specialization'] ?? 'عقارات وسيارات').toString(),
      avl: parsedAvl,
      activeTasksCount: int.tryParse(map['active_tasks_count']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nm': fullName,
      'ph': phone,
      'whatsapp_phone': whatsappPhone,
      'office_address': officeAddress,
      'specialization': specialization,
      'avl': avl,
      'active_tasks_count': activeTasksCount,
    };
  }
}
