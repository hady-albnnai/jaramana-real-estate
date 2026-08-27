/// 📣 حساب نشر اجتماعي (فيسبوك/إنستغرام) — يُدار من شاشة الإدارة.
///
/// المصدر: جدول `social_accounts` عبر Edge Function `social-accounts`.
/// ⚠️ التوكن الكامل لا يصل إلى التطبيق أبداً — فقط قناعه
/// (`tokenMasked` = آخر 4 محارف) وطوله، لأغراض التأكد البصري.
class SocialAccountModel {
  final String id;
  final String platform; // facebook | instagram
  final String name;
  final String accountExternalId; // Page ID لفيسبوك / IG Business ID
  final String verifiedName; // الاسم الحقيقي كما أعاده Graph API
  final String tokenMasked;
  final int tokenLength;
  final bool isActive;
  final bool isVerified;
  final String lastError;
  final DateTime? lastVerifiedAt;

  const SocialAccountModel({
    required this.id,
    required this.platform,
    required this.name,
    required this.accountExternalId,
    this.verifiedName = '',
    this.tokenMasked = '',
    this.tokenLength = 0,
    this.isActive = true,
    this.isVerified = false,
    this.lastError = '',
    this.lastVerifiedAt,
  });

  factory SocialAccountModel.fromMap(Map<String, dynamic> map) {
    DateTime? tryDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return SocialAccountModel(
      id: map['id']?.toString() ?? '',
      platform: map['platform']?.toString() ?? 'facebook',
      name: map['name']?.toString() ?? '',
      accountExternalId: map['accountExternalId']?.toString() ?? '',
      verifiedName: map['verifiedName']?.toString() ?? '',
      tokenMasked: map['tokenMasked']?.toString() ?? '',
      tokenLength: int.tryParse(map['tokenLength']?.toString() ?? '0') ?? 0,
      isActive: map['isActive'] == true,
      isVerified: map['isVerified'] == true,
      lastError: map['lastError']?.toString() ?? '',
      lastVerifiedAt: tryDate(map['lastVerifiedAt']),
    );
  }

  bool get isFacebook => platform == 'facebook';

  String get platformLabel => isFacebook ? 'فيسبوك' : 'إنستغرام';
}
