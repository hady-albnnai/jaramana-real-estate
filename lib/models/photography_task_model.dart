class PhotographyTaskModel {
  final String id;
  final String offId;
  final String photographerId;
  final String requestedBy;
  final String ttl;
  final String notes;
  final Map<String, dynamic> loc;
  final List<String> media;
  final String photographerNote;
  final String officeNote;
  final int sts;
  /// المهمة ناتجة عن طلب تصوير أنشأ مسودة عرض كاملة لدى المستخدم.
  final bool isPhotoRequestOffer;
  final int? offerStatus;
  final DateTime? tsScheduled;
  final DateTime? tsSubmit;
  final DateTime? tsDone;
  final DateTime tsCrt;
  final DateTime? tsUpd;

  PhotographyTaskModel({
    required this.id,
    required this.offId,
    this.photographerId = '',
    this.requestedBy = '',
    this.ttl = '',
    this.notes = '',
    Map<String, dynamic>? loc,
    List<String>? media,
    this.photographerNote = '',
    this.officeNote = '',
    this.sts = 0,
    this.isPhotoRequestOffer = false,
    this.offerStatus,
    this.tsScheduled,
    this.tsSubmit,
    this.tsDone,
    required this.tsCrt,
    this.tsUpd,
  })  : loc = loc ?? {},
        media = media ?? [];

  factory PhotographyTaskModel.fromSupabase(Map<String, dynamic> data, String id) {
    return PhotographyTaskModel(
      id: id,
      offId: data['off_id'] ?? '',
      photographerId: data['photographer_id'] ?? '',
      requestedBy: data['requested_by'] ?? '',
      ttl: data['ttl'] ?? '',
      notes: data['notes'] ?? '',
      loc: data['loc'] != null ? Map<String, dynamic>.from(data['loc'] as Map) : {},
      media: data['media'] != null ? List<String>.from(data['media'] as List) : [],
      photographerNote: data['photographer_note'] ?? '',
      officeNote: data['office_note'] ?? '',
      sts: data['sts'] ?? 0,
      isPhotoRequestOffer: data['is_photo_request'] == true || data['is_photo_request'] == 1,
      offerStatus: data['offer_sts'] == null ? null : int.tryParse(data['offer_sts'].toString()),
      tsScheduled: data['ts_scheduled'] != null ? DateTime.parse(data['ts_scheduled']) : null,
      tsSubmit: data['ts_submit'] != null ? DateTime.parse(data['ts_submit']) : null,
      tsDone: data['ts_done'] != null ? DateTime.parse(data['ts_done']) : null,
      tsCrt: DateTime.parse(data['ts_crt']),
      tsUpd: data['ts_upd'] != null ? DateTime.parse(data['ts_upd']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'off_id': offId,
      'photographer_id': photographerId.isEmpty ? null : photographerId,
      'requested_by': requestedBy.isEmpty ? null : requestedBy,
      'ttl': ttl,
      'notes': notes,
      'loc': loc,
      'media': media,
      'photographer_note': photographerNote,
      'office_note': officeNote,
      'sts': sts,
      'is_photo_request': isPhotoRequestOffer,
      'offer_sts': offerStatus,
      'ts_scheduled': tsScheduled?.toIso8601String(),
      'ts_submit': tsSubmit?.toIso8601String(),
      'ts_done': tsDone?.toIso8601String(),
      'ts_crt': tsCrt.toIso8601String(),
      'ts_upd': tsUpd?.toIso8601String(),
    };
  }

  bool get isPending => sts == 0;
  bool get isInProgress => sts == 1;
  bool get isSubmitted => sts == 2;
  bool get isApproved => sts == 3;
  bool get isRejected => sts == 4;
  bool get isCancelled => sts == 5;

  String get statusLabel {
    switch (sts) {
      case 0:
        return 'بانتظار المصور';
      case 1:
        return 'قيد التنفيذ';
      case 2:
        return 'مرسلة للمكتب';
      case 3:
        return 'معتمدة';
      case 4:
        return 'مرفوضة';
      case 5:
        return 'ملغاة';
      default:
        return 'غير معروف';
    }
  }
}
