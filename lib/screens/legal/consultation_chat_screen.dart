import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

class _ConsultationChatScreenState extends State<ConsultationChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _storage = StorageService();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic> _chatInfo = {};
  bool _loading = true;
  bool _sending = false;
  bool _refreshing = false;
  RealtimeChannel? _realtimeChannel;

  // ⚖️ سعر التجديد ومدة المحادثة من الإعدادات (2026-08-14) — كانا ثابتين نصاً
  int get _renewPrice =>
      context.read<ConfigProvider>().config?.legalRenewPrice ?? 500;
  int get _durationMins =>
      context.read<ConfigProvider>().config?.legalDurationMins ?? 15;
  static String _fmtPrice(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  String _lawyerAlias = 'محامي المكتب';

  Timer? _timer;
  int _remainingSeconds = 0;
  bool _timeUp = false; // الوقت خلص بس المحادثة لسه مفتوحة
  int _renewCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeRealtime();
      _loadMessages();
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _timer?.cancel();
    final channel = _realtimeChannel;
    if (channel != null) {
      unawaited(SupabaseService().client.removeChannel(channel));
    }
    super.dispose();
  }

  void _subscribeRealtime() {
    _realtimeChannel = SupabaseService().client
        .channel('consultation:${widget.consultationId}')
        .onBroadcast(
          event: 'messages_changed',
          callback: (_) => _loadMessages(),
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction(
        'legal-actions', body: {
          'action': 'get_chat_messages', 'user_uid': uid,
          'consultation_id': widget.consultationId,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        final msgs = List<Map<String, dynamic>>.from(data['messages'] as List? ?? []);
        final info = Map<String, dynamic>.from(data['chat_info'] as Map? ?? {});
        if (mounted) {
          setState(() {
            _messages = msgs;
            _chatInfo = info;
            _lawyerAlias = (info['lawyer_alias'] ?? 'محامي المكتب').toString();
            _remainingSeconds = (info['remaining_seconds'] ?? 0) as int;
            _timeUp = (info['chat_expired'] ?? false) as bool;
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
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_timeUp || _remainingSeconds <= 0) { setState(() => _timeUp = true); return; }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _timer?.cancel(); return; }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          if (_remainingSeconds == 180) _showAlert('⏱️ بقي 3 دقائق على انتهاء الوقت الحالي');
          if (_remainingSeconds == 60) _showAlert('⏱️ بقي دقيقة واحدة!');
        } else {
          _timeUp = true;
          _timer?.cancel();
        }
      });
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

  Future<void> _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    await _sendMessage('text', text);
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 1280);
    if (file == null) return;
    setState(() => _sending = true);
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
      final path = data?['path']?.toString() ?? '';
      if (data?['success'] != true || path.isEmpty) {
        throw Exception('CHAT_IMAGE_UPLOAD_FAILED');
      }
      await _sendMessage('image', '', fileUrl: path, fileName: file.name);
    } catch (e) { _showAlert('فشل رفع الصورة'); }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _sendMessage(String type, String content, {String? fileUrl, String? fileName, int? duration}) async {
    setState(() => _sending = true);
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'send_chat_message', 'user_uid': uid,
        'consultation_id': widget.consultationId,
        'message_type': type, 'content': content,
        'file_url': fileUrl ?? '', 'file_name': fileName ?? '',
        'duration_seconds': duration,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
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
  }

  Future<void> _renewChat() async {
    setState(() => _sending = true);
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      // التجديد بسعر الإعدادات (legalPrice.renew) — لا رقم ثابت
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'renew_chat', 'user_uid': uid,
        'consultation_id': widget.consultationId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        setState(() {
          _timeUp = false;
          _remainingSeconds = _durationMins * 60; // مدة جديدة من الإعدادات
          _renewCount = (data['renew_count'] ?? 0) as int;
        });
        _startTimer();
        await _loadMessages();
        _showAlert('✅ تم تجديد المحادثة $_durationMins دقيقة إضافية');
      } else {
        _showAlert(data?['error']?.toString() ?? 'فشل التجديد');
      }
    } catch (e) { _showAlert('خطأ: $e'); }
    if (mounted) setState(() => _sending = false);
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
    final isLawyer = context.read<AuthProvider>().isLawyer;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isLawyer ? 'الاستشارة' : _lawyerAlias, style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 15)),
          Row(children: [
            if (!_timeUp && _remainingSeconds > 0) ...[
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
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _messageBubble(_messages[i]),
                      ),
              ),
              // شريط الإدخال
              if (_timeUp && !isLawyer)
                _buildRenewBar()
              else if (_timeUp && isLawyer)
                _buildTimeUpInfo()
              else
                _buildInputBar(),
            ]),
    );
  }

  Widget _buildRenewBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), border: Border(top: BorderSide(color: AppTheme.warningOrange.withOpacity(0.3)))),
      child: Column(children: [
        const Text('⏱️ انتهى الوقت الحالي — يمكنك التجديد للمتابعة', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12)),
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
        IconButton(icon: const Icon(Icons.image, color: AppTheme.primaryGold), onPressed: _sending ? null : _sendImage),
        Expanded(child: TextField(controller: _msgCtrl, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'اكتب رسالتك...', hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: 13),
            filled: true, fillColor: AppTheme.scaffoldBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
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
            if (type == 'voice') Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.mic, color: AppTheme.primaryGold, size: 18), AppTheme.gapWidthSmall,
              Text('🎤 رسالة صوتية (${msg['duration_seconds'] ?? 0}ث)', style: const TextStyle(color: AppTheme.textWhite, fontSize: 12))]),
            const SizedBox(height: 2),
            Text(ts, style: const TextStyle(color: AppTheme.textGrey, fontSize: 10)),
          ]))),
        if (isMine) ...[AppTheme.gapWidthSmall, Icon(Icons.done_all, size: 14, color: msg['is_read'] == true ? AppTheme.infoBlue : AppTheme.textGrey)],
      ]));
  }
}
