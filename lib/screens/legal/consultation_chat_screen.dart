import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../services/storage_service.dart';

class ConsultationChatScreen extends StatefulWidget {
  final String consultationId;
  const ConsultationChatScreen({super.key, required this.consultationId});

  @override
  State<ConsultationChatScreen> createState() => _ConsultationChatScreenState();
}

class _ConsultationChatScreenState extends State<ConsultationChatScreen>
    with WidgetsBindingObserver {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _storage = StorageService();
  final _recorder = AudioRecorder();
  VideoPlayerController? _audioController;

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic> _chatInfo = {};
  bool _loading = true;
  bool _sending = false;
  bool _refreshing = false;
  bool _loadingOlder = false;
  bool _hasMore = false;
  bool _recording = false;
  bool _realtimeConnected = false;
  Map<String, dynamic>? _v2Session;
  int _joinWindowSeconds = 0;
  bool _endDialogShown = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _playingMessageId;
  RealtimeChannel? _realtimeChannel;

  // ⚖️ سعر التجديد ومدة المحادثة من الإعدادات (2026-08-14) — كانا ثابتين نصاً
  int get _renewPrice =>
      context.read<ConfigProvider>().config?.legalRenewPrice ?? 500;
  int get _durationMins =>
      context.read<ConfigProvider>().config?.legalDurationMins ?? 15;
  static String _fmtPrice(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  String _newClientMessageId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _lawyerAlias = 'محامي المكتب';

  Timer? _timer;
  int _remainingSeconds = 0;
  bool _timeUp = false; // الوقت خلص بس المحادثة لسه مفتوحة
  int _renewCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _subscribeRealtime();
      _restoreDraft();
      await _loadMessages();
      await _loadV2Session();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _timer?.cancel();
    _recordingTimer?.cancel();
    unawaited(_recorder.dispose());
    _audioController?.dispose();
    final channel = _realtimeChannel;
    if (channel != null) {
      unawaited(SupabaseService().client.removeChannel(channel));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
      _loadV2Session();
    }
  }

  void _subscribeRealtime() {
    _realtimeChannel = SupabaseService().client
        .channel('consultation:${widget.consultationId}')
        .onBroadcast(
          event: 'messages_changed',
          callback: (_) => _loadMessages(),
        )
        .onBroadcast(
          event: 'messages_read',
          callback: (_) async {
            // إن وصل حدث القراءة أثناء جلب سابق، نعيد المحاولة بعد مهلة قصيرة
            // بدل إسقاط الحدث بسبب _refreshing.
            await Future<void>.delayed(const Duration(milliseconds: 250));
            await _loadMessages();
          },
        )
        .onBroadcast(
          event: 'session_changed',
          callback: (_) async {
            await _loadMessages();
            await _loadV2Session();
          },
        )
        .subscribe((status, _) {
          if (!mounted) return;
          setState(() {
            _realtimeConnected =
                status == RealtimeSubscribeStatus.subscribed;
          });
        });
  }

  Future<void> _loadV2Session() async {
    if (context.read<ConfigProvider>().config?.consultationFlowV2 != true) return;
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'get_chat_session_v2',
        'user_uid': uid,
        'consultation_id': widget.consultationId,
      });
      final data = res.data as Map<String, dynamic>?;
      final session = data?['session'] is Map
          ? Map<String, dynamic>.from(data!['session'] as Map)
          : null;
      if (session == null || !mounted) return;
      final isLawyer = context.read<AuthProvider>().isLawyer;
      if (session['status'] == 'join_window' && !isLawyer) {
        final joined = await SupabaseService().invokeFunction('legal-actions', body: {
          'action': 'join_chat_session_v2',
          'user_uid': uid,
          'consultation_id': widget.consultationId,
          'idempotency_key': _newClientMessageId(),
        });
        final joinedData = joined.data as Map<String, dynamic>?;
        if (joinedData?['success'] == true) {
          await _loadMessages();
          await _loadV2Session();
          return;
        }
      }
      final status = (session['status'] ?? '').toString();
      setState(() {
        _v2Session = session;
        _joinWindowSeconds = (data?['seconds_until_auto_start'] ?? 0) as int;
        _remainingSeconds = (data?['remaining_seconds'] ?? 0) as int;
        _timeUp = status == 'ended';
      });
      if (_timeUp && !isLawyer && !_endDialogShown) {
        _endDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showEndOptions());
      }
    } catch (_) {
      // تبقى قراءة الرسائل القديمة مساراً احتياطياً أثناء الانتقال.
    }
  }

  Future<void> _loadMessages({bool older = false}) async {
    if (_refreshing || (older && _loadingOlder)) return;
    _refreshing = true;
    if (older && mounted) setState(() => _loadingOlder = true);
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction(
        'legal-actions', body: {
          'action': 'get_chat_messages', 'user_uid': uid,
          'consultation_id': widget.consultationId,
          'limit': 50,
          if (older && _messages.isNotEmpty)
            'before': _messages.first['ts_crt']?.toString() ?? '',
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        final msgs = List<Map<String, dynamic>>.from(data['messages'] as List? ?? []);
        final info = Map<String, dynamic>.from(data['chat_info'] as Map? ?? {});
        if (mounted) {
          setState(() {
            _messages = older ? [...msgs, ..._messages] : msgs;
            _hasMore = data['has_more'] == true;
            _loadingOlder = false;
            _chatInfo = info;
            _lawyerAlias = (info['lawyer_alias'] ?? 'محامي المكتب').toString();
            _remainingSeconds = (info['remaining_seconds'] ?? 0) as int;
            _timeUp = (info['chat_expired'] ?? false) as bool;
            _renewCount = (info['renew_count'] ?? 0) as int;
            _loading = false;
          });
          _startTimer();
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _refreshing = false;
      if (mounted && _loadingOlder) setState(() => _loadingOlder = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_timeUp || _remainingSeconds <= 0) { setState(() => _timeUp = true); return; }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _timer?.cancel(); return; }
      var refreshV2 = false;
      setState(() {
        if (_joinWindowSeconds > 0) {
          _joinWindowSeconds--;
          refreshV2 = _joinWindowSeconds == 0;
        }
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          if (_remainingSeconds == 180) _showAlert('⏱️ بقي 3 دقائق على انتهاء الوقت الحالي');
          if (_remainingSeconds == 60) _showAlert('⏱️ بقي دقيقة واحدة!');
        } else {
          _timeUp = true;
          _timer?.cancel();
        }
      });
      if (refreshV2) unawaited(_loadV2Session());
    });
  }

  void _showAlert(String msg) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(msg), backgroundColor: AppTheme.warningOrange));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _daysRemaining {
    final startedAt = _chatInfo['chat_started_at'];
    if (startedAt == null) return 0;
    final dt = DateTime.tryParse(startedAt.toString());
    if (dt == null) return 0;
    final diff = 7 - DateTime.now().difference(dt).inDays;
    return diff > 0 ? diff : 0;
  }

  String get _draftKey => 'consultation_chat_draft_${widget.consultationId}';

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(_draftKey) ?? '';
    if (mounted && draft.isNotEmpty) _msgCtrl.text = draft;
  }

  Future<void> _saveDraft(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.trim().isEmpty) {
      await prefs.remove(_draftKey);
    } else {
      await prefs.setString(_draftKey, value);
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      _recordingTimer?.cancel();
      final duration = _recordingSeconds;
      if (mounted) setState(() { _recording = false; _recordingSeconds = 0; });
      if (path != null && duration > 0) await _sendVoice(path, duration);
      return;
    }
    if (!await _recorder.hasPermission()) {
      _showAlert('يلزم السماح باستخدام الميكروفون لتسجيل رسالة صوتية');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (!mounted) return;
    setState(() { _recording = true; _recordingSeconds = 0; });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || !_recording) return;
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= 60) await _toggleRecording();
    });
  }

  Future<void> _discardUploadedFile(String path) async {
    if (path.isEmpty) return;
    try {
      await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'discard_chat_upload',
        'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'consultation_id': widget.consultationId,
        'path': path,
      });
    } catch (_) {
      // مهمة التنظيف الدورية تبقى خط الدفاع الأخير.
    }
  }

  Future<void> _sendVoice(String path, int duration) async {
    setState(() => _sending = true);
    var remotePath = '';
    try {
      final bytes = await File(path).readAsBytes();
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final response = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'upload_chat_voice', 'user_uid': uid,
        'consultation_id': widget.consultationId,
        'file_base64': base64Encode(bytes), 'duration_seconds': duration,
      });
      final data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null;
      remotePath = data?['path']?.toString() ?? '';
      if (data?['success'] != true || remotePath.isEmpty) throw Exception();
      final sent = await _sendMessage('voice', '', fileUrl: remotePath,
          fileName: 'رسالة صوتية.m4a', duration: duration);
      if (!sent) await _discardUploadedFile(remotePath);
    } catch (_) {
      if (remotePath.isNotEmpty) await _discardUploadedFile(remotePath);
      _showAlert('فشل إرسال الرسالة الصوتية');
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _playVoice(Map<String, dynamic> msg) async {
    final url = (msg['file_signed_url'] ?? msg['file_url'] ?? '').toString();
    if (url.isEmpty) return;
    final id = msg['id']?.toString() ?? url;
    final current = _audioController;
    if (_playingMessageId == id && current != null && current.value.isPlaying) {
      await current.pause();
      if (mounted) setState(() {});
      return;
    }
    await current?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _audioController = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _playingMessageId = id);
      await controller.play();
      void listener() {
        if (!controller.value.isInitialized) return;
        if (controller.value.position >= controller.value.duration &&
            !controller.value.isPlaying) {
          controller.removeListener(listener);
          if (mounted) setState(() => _playingMessageId = null);
        }
      }
      controller.addListener(listener);
    } catch (_) {
      if (mounted) {
        setState(() => _playingMessageId = null);
        _showAlert('تعذّر تشغيل الرسالة الصوتية');
      }
    }
  }

  Future<void> _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final sent = await _sendMessage('text', text);
    if (sent) {
      _msgCtrl.clear();
      await _saveDraft('');
    }
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 1280);
    if (file == null) return;
    setState(() => _sending = true);
    var remotePath = '';
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final bytes = kIsWeb
          ? await file.readAsBytes()
          : await (await _storage.compressImage(File(file.path)) ?? File(file.path))
              .readAsBytes();
      final response = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {
          'action': 'upload_chat_image',
          'user_uid': uid,
          'consultation_id': widget.consultationId,
          'file_base64': base64Encode(bytes),
        },
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : null;
      remotePath = data?['path']?.toString() ?? '';
      if (data?['success'] != true || remotePath.isEmpty) {
        throw Exception('CHAT_IMAGE_UPLOAD_FAILED');
      }
      final sent = await _sendMessage('image', '', fileUrl: remotePath, fileName: file.name);
      if (!sent) await _discardUploadedFile(remotePath);
    } catch (_) {
      if (remotePath.isNotEmpty) await _discardUploadedFile(remotePath);
      _showAlert('فشل رفع الصورة');
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<bool> _sendMessage(String type, String content, {String? fileUrl, String? fileName, int? duration}) async {
    setState(() => _sending = true);
    var sent = false;
    final clientMessageId = _newClientMessageId();
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'send_chat_message', 'user_uid': uid,
        'consultation_id': widget.consultationId,
        'message_type': type, 'content': content,
        'file_url': fileUrl ?? '', 'file_name': fileName ?? '',
        'duration_seconds': duration, 'client_message_id': clientMessageId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        sent = true;
        await _loadMessages();
      } else {
        final error = data?['error']?.toString() ?? '';
        if (error == 'CHAT_EXPIRED_7DAYS') {
          _showAlert('انتهت صلاحية المحادثة (7 أيام)');
        } else if (error == 'CHAT_TIME_EXPIRED') {
          _timeUp = true;
          _showAlert('انتهى وقت المحادثة — يلزم التجديد للمتابعة');
        } else {
          _showAlert('فشل إرسال الرسالة');
        }
      }
    } catch (e) { _showAlert('فشل إرسال الرسالة'); }
    if (mounted) setState(() => _sending = false);
    return sent;
  }

  Future<void> _showEndOptions() async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('انتهى وقت الاستشارة',
            style: TextStyle(color: AppTheme.primaryGold)),
        content: const Text(
          'يمكنك متابعة المحادثة مع المحامي نفسه، أو تحويل القضية إلى جلسة حضورية، أو إنهاؤها وتقييم الخدمة.',
          style: TextStyle(color: AppTheme.textWhite, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'later'),
              child: const Text('لاحقاً')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'onsite'),
              child: const Text('تحويل إلى حضورية')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'renew'),
              child: const Text('تجديد المحادثة')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'rate'),
              child: const Text('إنهاء وتقييم')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'renew') {
      context.push('/legal/consultations?flow=phone_renew&parent=${widget.consultationId}');
    } else if (choice == 'onsite') {
      context.push('/legal/consultations?flow=onsite_convert&parent=${widget.consultationId}');
    } else if (choice == 'rate') {
      _showRatingDialog();
    }
  }

  Future<void> _renewChat() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تجديد المحادثة',
            style: TextStyle(color: AppTheme.primaryGold)),
        content: Text(
          'سيتم نقلك إلى قسم الاستشارة لإنشاء طلب دفع بقيمة '
          '${_fmtPrice(_renewPrice)} ل.س. لا تُضاف المدة إلا بعد اعتماد الدفعة من الإدارة.',
          style: const TextStyle(color: AppTheme.textWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('متابعة إلى الدفع'),
          ),
        ],
      ),
    );
    if (proceed == true && mounted) {
      context.push('/legal/consultations?flow=phone_renew&parent=${widget.consultationId}');
    }
  }

  Future<void> _showReportDialog() async {
    final detailsCtrl = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('إبلاغ الإدارة عن مشكلة',
            style: TextStyle(color: AppTheme.primaryGold)),
        content: TextField(
          controller: detailsCtrl,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(
            hintText: 'اشرح المشكلة بوضوح دون كتابة معلومات غير ضرورية',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال البلاغ')),
        ],
      ),
    );
    final details = detailsCtrl.text.trim();
    detailsCtrl.dispose();
    if (submit != true || details.length < 10 || !mounted) {
      if (submit == true && details.length < 10) {
        _showAlert('يرجى كتابة تفاصيل أوضح للمشكلة');
      }
      return;
    }
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'report_consultation_issue',
        'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'consultation_id': widget.consultationId,
        'details': details,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        _showAlert('تم إرسال البلاغ إلى الإدارة');
      } else if (data?['error'] == 'REPORT_ALREADY_OPEN') {
        _showAlert('يوجد بلاغ مفتوح لهذه الاستشارة بالفعل');
      } else {
        _showAlert('تعذّر إرسال البلاغ');
      }
    } catch (_) {
      _showAlert('تعذّر إرسال البلاغ');
    }
  }

  void _showRatingDialog() {
    int rating = 5;
    final commentCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setS) => AlertDialog(
      backgroundColor: AppTheme.surfaceBlack,
      title: const Text('تقييم الاستشارة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => GestureDetector(
          onTap: () => setS(() => rating = i + 1),
          child: Icon(Icons.star, color: i < rating ? AppTheme.primaryGold : AppTheme.textGrey, size: 32),
        ))),
        AppTheme.gapHeightMedium,
        TextField(controller: commentCtrl, maxLines: 2, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'تعليق (اختياري)', filled: true, fillColor: AppTheme.scaffoldBackground, border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey))),
        ElevatedButton(onPressed: () async {
          try {
            await SupabaseService().invokeFunction('legal-actions', body: {
              'action': 'rate_consultation', 'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
              'consultation_id': widget.consultationId, 'rating': rating, 'comment': commentCtrl.text.trim(),
            });
            if (ctx2.mounted) Navigator.pop(ctx2);
            _showAlert('✅ شكراً لتقييمك!');
          } catch (_) { _showAlert('فشل إرسال التقييم'); }
        }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold), child: const Text('إرسال', style: TextStyle(color: Colors.black))),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isLawyer = auth.isLawyer;
    final isReadOnlyAdmin = auth.isManager;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isLawyer ? 'الاستشارة' : _lawyerAlias, style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 15)),
          Row(children: [
            if (_v2Session?['status'] == 'join_window') ...[
              const Icon(Icons.hourglass_top, size: 12, color: AppTheme.warningOrange),
              const SizedBox(width: 4),
              Text('مهلة الانضمام ${_formatTime(_joinWindowSeconds)}',
                  style: const TextStyle(color: AppTheme.warningOrange, fontSize: 11)),
            ] else if (!_timeUp && _remainingSeconds > 0) ...[
              Icon(Icons.timer, size: 12, color: _remainingSeconds <= 180 ? AppTheme.warningOrange : AppTheme.textGrey),
              const SizedBox(width: 4),
              Text(_formatTime(_remainingSeconds), style: TextStyle(color: _remainingSeconds <= 180 ? AppTheme.warningOrange : AppTheme.textGrey, fontSize: 11)),
            ],
            if (_timeUp) ...[
              const Icon(Icons.timer_off, size: 12, color: AppTheme.warningOrange),
              const SizedBox(width: 4),
              const Text('انتهى الوقت — جدد للمتابعة', style: TextStyle(color: AppTheme.warningOrange, fontSize: 11)),
            ],
            if (_daysRemaining > 0 && _daysRemaining <= 3) ...[
              const SizedBox(width: 8),
              Text('📅 $_daysRemaining أيام متبقية', style: const TextStyle(color: AppTheme.errorRed, fontSize: 10)),
            ],
          ]),
        ]),
        actions: [
          Tooltip(
            message: _realtimeConnected
                ? 'متصل — الرسائل تتحدث فورياً'
                : 'جارٍ استعادة الاتصال',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                _realtimeConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                size: 18,
                color: _realtimeConnected ? AppTheme.successGreen : AppTheme.warningOrange,
              ),
            ),
          ),
          if (!isLawyer && !isReadOnlyAdmin)
            IconButton(
              tooltip: 'إبلاغ الإدارة عن مشكلة',
              onPressed: _showReportDialog,
              icon: const Icon(Icons.flag_outlined, color: AppTheme.primaryGold),
            ),
        ],
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : Column(children: [
              Expanded(
                child: _messages.isEmpty
                    ? const Center(child: Text('لا توجد رسائل بعد', style: TextStyle(color: AppTheme.textGrey)))
                    : ListView.builder(
                        controller: _scrollCtrl, padding: AppTheme.paddingAllMedium,
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (_hasMore && i == 0) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: _loadingOlder
                                    ? null
                                    : () => _loadMessages(older: true),
                                icon: _loadingOlder
                                    ? const SizedBox(width: 14, height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.history),
                                label: const Text('تحميل رسائل أقدم'),
                              ),
                            );
                          }
                          final index = _hasMore ? i - 1 : i;
                          return _messageBubble(_messages[index]);
                        },
                      ),
              ),
              // شريط الإدخال
              if (isReadOnlyAdmin)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                      12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
                  color: AppTheme.surfaceBlack,
                  child: const Text(
                    'وضع رقابي للمدير — مشاهدة فقط دون تغيير حالة القراءة',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.infoBlue, fontSize: 12),
                  ),
                )
              else if (_v2Session?['status'] == 'ready')
                _buildSessionWaitingBar('بانتظار استعداد المحامي لبدء الجلسة')
              else if (_v2Session?['status'] == 'join_window')
                _buildSessionWaitingBar(
                  'بانتظار انضمام العميل — يبدأ العداد تلقائياً خلال ${_formatTime(_joinWindowSeconds)}',
                )
              else if (_timeUp && !isLawyer)
                _buildRenewBar()
              else if (_timeUp && isLawyer)
                _buildTimeUpInfo()
              else
                _buildInputBar(),
            ]),
    );
  }

  Widget _buildSessionWaitingBar(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        12, 12, 12, 12 + MediaQuery.of(context).padding.bottom,
      ),
      color: AppTheme.surfaceBlack,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.warningOrange, fontSize: 12),
      ),
    );
  }

  Widget _buildRenewBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), border: Border(top: BorderSide(color: AppTheme.warningOrange.withOpacity(0.3)))),
      child: Column(children: [
        const Text('⏱️ انتهى الوقت الحالي — يمكنك التجديد للمتابعة', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12)),
        Text(
          'المدة المسجلة: ${_chatInfo['chat_duration_minutes'] ?? _durationMins} دقيقة'
          '${_renewCount > 0 ? ' • مرات التجديد: $_renewCount' : ''}',
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 11),
        ),
        AppTheme.gapHeightSmall,
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _sending ? null : _renewChat,
            icon: const Icon(Icons.refresh, size: 16, color: Colors.black),
            label: Text('تجديد $_durationMins دقيقة — ${_fmtPrice(_renewPrice)} ل.س', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          )),
        ]),
        AppTheme.gapHeightSmall,
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          TextButton.icon(onPressed: _showRatingDialog, icon: const Icon(Icons.star, size: 16, color: AppTheme.primaryGold),
            label: const Text('تقييم', style: TextStyle(color: AppTheme.primaryGold, fontSize: 12))),
        ]),
      ]),
    );
  }

  Widget _buildTimeUpInfo() {
    return Container(
      padding: EdgeInsets.all(12 + MediaQuery.of(context).padding.bottom * 0.5),
      color: AppTheme.surfaceBlack,
      child: const Center(child: Text('⏱️ انتهى الوقت — بانتظار تجديد العميل', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12))),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: AppTheme.surfaceBlack, border: Border(top: BorderSide(color: Colors.white12))),
      child: Row(children: [
        IconButton(
          icon: Icon(_recording ? Icons.stop_circle : Icons.mic,
              color: _recording ? AppTheme.errorRed : AppTheme.primaryGold),
          onPressed: _sending ? null : _toggleRecording,
        ),
        if (_recording)
          Text(_formatTime(_recordingSeconds),
              style: const TextStyle(color: AppTheme.errorRed, fontSize: 11)),
        IconButton(icon: const Icon(Icons.image, color: AppTheme.primaryGold), onPressed: _sending ? null : _sendImage),
        Expanded(child: TextField(controller: _msgCtrl, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'اكتب رسالتك...', hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: 13),
            filled: true, fillColor: AppTheme.scaffoldBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          onChanged: _saveDraft,
          onSubmitted: (_) => _sendText())),
        AppTheme.gapWidthSmall,
        _sending
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryGold))
            : IconButton(icon: const Icon(Icons.send, color: AppTheme.primaryGold), onPressed: _sendText),
      ]),
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg) {
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final isMine = msg['sender_id'] == uid;
    final type = (msg['message_type'] ?? 'text').toString();
    final content = (msg['content'] ?? '').toString();
    final ts = msg['ts_crt']?.toString().substring(11, 16) ?? '';

    if (type == 'system') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(content, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11), textAlign: TextAlign.center))));
    }

    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(
      mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMine) ...[
          CircleAvatar(radius: 12, backgroundColor: AppTheme.primaryGold.withOpacity(0.3), child: const Icon(Icons.person, size: 14, color: AppTheme.primaryGold)),
          AppTheme.gapWidthSmall,
        ],
        Flexible(child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMine ? AppTheme.primaryGold.withOpacity(0.2) : AppTheme.surfaceBlack,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isMine ? 12 : 4), bottomRight: Radius.circular(isMine ? 4 : 12))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (type == 'text') Text(content, style: const TextStyle(color: AppTheme.textWhite, fontSize: 13, height: 1.4)),
            if (type == 'image' && (msg['file_signed_url'] != null || msg['file_url'] != null))
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(
                msg['file_signed_url']?.toString() ?? msg['file_url'].toString(),
                width: 200, height: 150, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppTheme.textGrey, size: 40))),
            if (type == 'voice') InkWell(
              onTap: () => _playVoice(msg),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_playingMessageId == msg['id']?.toString() &&
                        (_audioController?.value.isPlaying ?? false)
                    ? Icons.pause_circle
                    : Icons.play_circle,
                    color: AppTheme.primaryGold, size: 28),
                AppTheme.gapWidthSmall,
                Text('رسالة صوتية (${msg['duration_seconds'] ?? 0}ث)',
                    style: const TextStyle(color: AppTheme.textWhite, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(ts, style: const TextStyle(
                  color: AppTheme.textGrey, fontSize: 10)),
              if (isMine) ...[
                const SizedBox(width: 5),
                Icon(
                  msg['is_read'] == true ? Icons.done_all : Icons.done,
                  size: 13,
                  color: msg['is_read'] == true
                      ? AppTheme.infoBlue
                      : AppTheme.textGrey,
                ),
                const SizedBox(width: 3),
                Text(
                  msg['is_read'] == true ? 'تمت القراءة' : 'تم الإرسال',
                  style: TextStyle(
                    color: msg['is_read'] == true
                        ? AppTheme.infoBlue
                        : AppTheme.textGrey,
                    fontSize: 9,
                  ),
                ),
              ],
            ]),
          ]))),
      ]));
  }
}
