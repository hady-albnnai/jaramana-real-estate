import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../core/network/supabase_service.dart';
import '../core/utils/error_utils.dart';
import 'auth_service.dart';

/// خدمة التخزين — رفع الصور والملفات إلى Supabase Storage
/// مع اختيار من المعرض/الكاميرا وضغط الصور قبل الرفع.
/// المرحلة: رفع عبر Edge Function (upload-offer-images) بدلاً من RLS المباشرة
/// لأن التطبيق يستخدم custom auth (staff_session_token / JWT من الـ Edge Function).
class StorageService {
  final SupabaseStorageClient _storage = SupabaseService().storage;
  final ImagePicker _picker = ImagePicker();

  static const String offerBucket = 'offer_images';
  static const String configAssetsBucket = 'config_assets';
  static const String paymentProofsBucket = 'payment_proofs';
  // 🔒 Phase 9: bucket خاص لصور الهوية (private bucket — RLS صارمة)
  static const String idsPrivateBucket = 'ids_private';
  static const int maxImages = 6;

  String? _lastError;
  String? get lastError => _lastError;

  void clearError() => _lastError = null;

  void _setError(Object? error) {
    _lastError = ErrorUtils.arabicMessage(error);
  }

  /// كشف نوع صورة من البايتات الأولى (jpeg/png/webp) — jpeg كسقوط آمن.
  static String detectImageContentType(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  /// 🛡️ دين 1 (2026-08-20): رفع إثبات الدفع عبر توقيع الخادم + PUT مباشر
  /// بالتقدم — بدل الرفع المباشر القديم (بابه المفتوح يُقفل بالميغريشن).
  /// يعيد المسار البعيد (`{uid}/{اليوم}/{uuid}.jpg`) أو null عند أي فشل —
  /// بما فيه تجاوز الحصة اليومية (10/يوم).
  static Future<String?> uploadPaymentProofSigned({
    required String uid,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final contentType = detectImageContentType(bytes);
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'sign_payment_proof_upload',
        'user_uid': uid,
        'content_type': contentType,
        'size_bytes': bytes.length,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      final uploadUrl = data?['upload_url']?.toString() ?? '';
      final fileUrl = data?['file_url']?.toString() ?? '';
      if (data?['success'] != true || uploadUrl.isEmpty || fileUrl.isEmpty) {
        return null;
      }
      final client = HttpClient();
      try {
        final req = await client.putUrl(Uri.parse(uploadUrl));
        req.headers.contentType = ContentType.parse(contentType);
        req.contentLength = bytes.length;
        const chunk = 64 * 1024;
        for (var i = 0; i < bytes.length; i += chunk) {
          final end = (i + chunk > bytes.length) ? bytes.length : i + chunk;
          req.add(bytes.sublist(i, end));
          onProgress?.call(end / bytes.length);
          await Future<void>.delayed(Duration.zero);
        }
        final resp = await req.close();
        await resp.drain<void>();
        if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      } finally {
        client.close();
      }
      return fileUrl;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════
  // اختيار الصور
  // ═══════════════════════════════════════

  /// اختيار صورة واحدة من المعرض أو الكاميرا
  Future<XFile?> pickImage({bool fromCamera = false}) async {
    try {
      return await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 1280,
      );
    } catch (e) {
      _setError(e);
      return null;
    }
  }

  /// اختيار عدة صور من المعرض (مع حد أقصى)
  Future<List<XFile>> pickMultiImages({int limit = maxImages}) async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 60, maxWidth: 1280);
      if (files.length > limit) return files.sublist(0, limit);
      return files;
    } catch (e) {
      _setError(e);
      return [];
    }
  }

  // ═══════════════════════════════════════
  // الضغط
  // ═══════════════════════════════════════

  /// ضغط صورة (يتخطى الضغط على الويب لعدم توفّر المسارات)
  /// الجودة الافتراضية 50% مع حد أقصى 1024 بكسل لضغط أقوى
  Future<File?> compressImage(File file, {int quality = 50}) async {
    if (kIsWeb) return file;
    try {
      final dir = await getTemporaryDirectory();
      final target =
          '${dir.path}/cmp_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        target,
        quality: quality,
        minWidth: 1024,
        minHeight: 1024,
      );
      if (result == null) return file;
      return File(result.path);
    } catch (e) {
      _setError(e);
      return file; // عند الفشل نرفع الأصلي
    }
  }

  // ═══════════════════════════════════════
  // رفع عبر Edge Function (الجديد)
  // ═══════════════════════════════════════

  /// يبني رابط Edge Function (يفترض نفس الدومين أو supabase.functions.url)
  String get _edgeUrl {
    if (SupabaseService.url == null || SupabaseService.publishableKey == null) {
      throw 'Supabase not initialized';
    }
    return '${SupabaseService.url!}/functions/v1/upload-offer-images';
  }

  /// يحاول الحصول على access token صالح للرفع (يستخدم الدالة المركزية)
  Future<String?> _getValidAccessToken() async {
    return await SupabaseService().getValidAccessToken();
  }

  /// رفع ملفات عبر Edge Function `upload-offer-images`.
  /// [files] : قائمة ملفات (Uint8List + اسم الملف).
  /// [userId] : مجلد المستخدم (uid).
  /// [offerId] : مجلد العرض (أو 'draft').
  /// [folder] : 'offers' | 'images' | 'videos' — يتفق مع storage_service القديم.
  Future<List<String>> _uploadViaEdgeFunction({
    required List<({Uint8List bytes, String name})> files,
    required String userId,
    String? offerId,
    String folder = 'offers',
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_edgeUrl));

      // Headers
      final headers = <String, String>{
        'apikey': SupabaseService.publishableKey!,
      };

      // ✅ نحصل على access token صالح (مع تحديث تلقائي إذا لزم)
      final accessToken = await _getValidAccessToken();
      if (accessToken != null) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
      // ❌ لا نستخدم anon key كبديل لأن الـ Edge Function بتُرفضه حتماً
      // إذا ما في توكن صالح، بنعتمد على staff_session_token فقط

      // إذا كان هناك staff_session_token (من AuthService) نضيفه
      final staffToken = await AuthService().getStaffSessionToken();
      if (staffToken != null && staffToken.isNotEmpty) {
        headers['x-staff-session-token'] = staffToken;
      }

      // ✅ إذا ما في JWT ولا staff_session_token → لا نستطيع الرفع
      if (accessToken == null && (staffToken == null || staffToken.isEmpty)) {
        throw StorageException(
          'لا يوجد جلسة نشطة — سجّل دخولك مجدداً وحاول',
        );
      }

      request.headers.addAll(headers);

      // Fields
      request.fields['user_id'] = userId;
      request.fields['admin_uid'] = userId;
      request.fields['offer_id'] = offerId ?? 'draft';
      request.fields['folder'] = folder;

      for (final f in files) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            f.bytes,
            filename: f.name,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      // مهلة زمنية صريحة — وإلا قد يبقى الرفع معلقاً للأبد على اتصال متقطع
      final response = await request.send().timeout(
        const Duration(seconds: 75),
        onTimeout: () => throw StorageException(
          'انتهت مهلة رفع الصور — تحقق من جودة الاتصال بالإنترنت وحاول مجدداً',
        ),
      );
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      if (response.statusCode != 200 || data['success'] != true) {
        throw StorageException(
          data['error']?.toString() ?? 'UPLOAD_FAILED',
          statusCode: response.statusCode.toString(),
        );
      }

      return (data['urls'] as List<dynamic>).cast<String>();
    } catch (e) {
      _setError(e);
      rethrow;
    }
  }

  // ═══════════════════════════════════════
  // الرفع (مُحدّث ليستخدم Edge Function)
  // ═══════════════════════════════════════

  /// رفع صورة عرض واحدة (مع ضغط) وإرجاع الرابط العام
  Future<String?> uploadOfferImage({
    required XFile xfile,
    required String userId,
    String? offerId,
  }) async {
    try {
      Uint8List bytes;
      if (kIsWeb) {
        bytes = await xfile.readAsBytes();
      } else {
        final compressed = await compressImage(File(xfile.path));
        bytes = await (compressed ?? File(xfile.path)).readAsBytes();
      }

      if (bytes.isEmpty) {
        _setError('Compressed image is empty');
        return null;
      }

      final urls = await _uploadViaEdgeFunction(
        files: [(bytes: bytes, name: xfile.name)],
        userId: userId,
        offerId: offerId,
        folder: 'offers',
      );
      return urls.isNotEmpty ? urls.first : null;
    } catch (e) {
      _setError(e);
      // ✅ لا نرجع null بصمت — نرمي الخطأ ليتم التقاطه في الشاشة
      rethrow;
    }
  }

  /// رفع عدة صور عرض وإرجاع قائمة الروابط الناجحة
  Future<List<String>> uploadOfferImages({
    required List<XFile> files,
    required String userId,
    String? offerId,
    void Function(int done, int total)? onProgress,
  }) async {
    final urls = <String>[];
    int failedCount = 0;
    for (var i = 0; i < files.length; i++) {
      try {
        final url = await uploadOfferImage(
          xfile: files[i],
          userId: userId,
          offerId: offerId,
        );
        if (url != null) {
          urls.add(url);
        } else {
          failedCount++;
        }
      } catch (e) {
        failedCount++;
        _setError(e);
      }
      onProgress?.call(i + 1, files.length);
    }
    // ✅ إذا كل الصور فشلت، نرمي استثناء صريح
    if (failedCount == files.length && files.isNotEmpty) {
      throw StorageException('رفع جميع الصور فشل — تحقق من اتصال الإنترنت وحاول مجدداً');
    }
    return urls;
  }

  // ═══════════════════════════════════════
  // دوال عامة (متوافقة مع الكود القديم)
  // ═══════════════════════════════════════

  Future<String> uploadImage({
    required File file,
    required String path,
    String? userId,
  }) async {
    final bytes = await file.readAsBytes();
    final urls = await _uploadViaEdgeFunction(
      files: [(bytes: bytes, name: path)],
      userId: userId ?? 'anonymous',
      folder: 'images',
    );
    return urls.first;
  }

  Future<String> uploadFile({
    required File file,
    required String bucket,
    required String path,
  }) async {
    // للـ buckets الأخرى (config_assets, payment_proofs) نحتفظ بالرفع المباشر
    // لأنها تستخدم RLS مختلفة أو service_role من Edge Functions أخرى
    if (bucket == offerBucket) {
      final bytes = await file.readAsBytes();
      final urls = await _uploadViaEdgeFunction(
        files: [(bytes: bytes, name: path)],
        userId: 'anonymous',
        folder: 'offers',
      );
      return urls.first;
    }

    final fileBytes = await file.readAsBytes();
    await _storage.from(bucket).uploadBinary(
      path,
      fileBytes,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
    );
    return _storage.from(bucket).getPublicUrl(path);
  }

  // ═══════════════════════════════════════
  // 🎬 الفيديو (المرحلة D)
  // ═══════════════════════════════════════

  /// اختيار فيديو من المعرض (الحد الأقصى: 60 ثانية لتوفير المساحة)
  Future<XFile?> pickVideo({Duration maxDuration = const Duration(seconds: 60)}) async {
    try {
      return await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: maxDuration,
      );
    } catch (e) {
      _setError(e);
      return null;
    }
  }

  /// رفع فيديو لعرض
  Future<String?> uploadOfferVideo({
    required XFile xfile,
    required String userId,
    String? offerId,
  }) async {
    try {
      final bytes = kIsWeb
          ? await xfile.readAsBytes()
          : await File(xfile.path).readAsBytes();

      // فحص الحجم (حد أقصى 50 MB)
      if (bytes.length > 50 * 1024 * 1024) {
        return null;
      }

      final urls = await _uploadViaEdgeFunction(
        files: [(bytes: bytes, name: xfile.name)],
        userId: userId,
        offerId: offerId,
        folder: 'videos',
      );
      return urls.isNotEmpty ? urls.first : null;
    } catch (e) {
      _setError(e);
      return null;
    }
  }

  Future<void> deleteFile(String bucket, String path) async {
    try {
      await _storage.from(bucket).remove([path]);
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> deleteImage(String url) async {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final idx = segments.indexOf('public');
      if (idx + 1 < segments.length) {
        final bucket = segments[idx + 1];
        final filePath = segments.sublist(idx + 2).join('/');
        await _storage.from(bucket).remove([filePath]);
      }
    } catch (e) {
      _setError(e);
    }
  }
}

/// Exception بسيط لحمل رسائل الـ Edge Function
class StorageException implements Exception {
  final String message;
  final String statusCode;
  StorageException(this.message, {this.statusCode = ''});
  @override
  String toString() => 'StorageException: $message (status: $statusCode)';
}
