import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../models/expediting_task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/legal_provider.dart';

class ExpediterTaskDetailScreen extends StatefulWidget {
  final ExpeditingTaskModel task;
  const ExpediterTaskDetailScreen({super.key, required this.task});

  @override
  State<ExpediterTaskDetailScreen> createState() => _ExpediterTaskDetailScreenState();
}

class _ExpediterTaskDetailScreenState extends State<ExpediterTaskDetailScreen> {
  late List<ChecklistItemModel> _items;
  late int _taskStatus;
  bool _completingTask = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.task.checklist);
    _taskStatus = widget.task.status;
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  Future<void> _updateItem(
    ChecklistItemModel item,
    int newSts,
    String inputVal,
    String attachUrl,
    String notes, {
    String attachmentBase64 = '',
    String attachmentContentType = 'image/jpeg',
  }) async {
    final prov = context.read<LegalProvider>();
    prov.setActor(context.read<AuthProvider>().userModel?.uid ?? '');
    final ok = await prov.updateChecklistItem(
      taskId: widget.task.id,
      itemKey: item.key,
      status: newSts,
      inputValue: inputVal,
      attachmentUrl: attachUrl,
      attachmentBase64: attachmentBase64,
      attachmentContentType: attachmentContentType,
      notes: notes,
    );
    if (ok && mounted) {
      _snack('✅ تم تحديث بند "${item.title}" بنجاح');
      setState(() {
        final idx = _items.indexWhere((e) => e.key == item.key);
        if (idx != -1) {
          _items[idx] = ChecklistItemModel(
            key: item.key,
            title: item.title,
            status: newSts,
            inputValue: inputVal,
            attachmentUrl: attachmentBase64.isNotEmpty ? attachUrl : (attachUrl.isNotEmpty ? attachUrl : item.attachmentUrl),
            attachmentSignedUrl: attachmentBase64.isNotEmpty ? '' : item.attachmentSignedUrl,
            notes: notes,
            revisionNotes: item.revisionNotes,
            requiredCopies: item.requiredCopies,
            lawyerInstructions: item.lawyerInstructions,
          );
        }
      });
    } else {
      _snack('فشل تحديث البند');
    }
  }

  bool get _allItemsDone => _items.isNotEmpty && _items.every((item) => item.status == 2);

  Future<void> _completeTask() async {
    if (!_allItemsDone) {
      _snack('يجب تعليم كل البنود كـ تم الاستخراج قبل إتمام المهمة');
      return;
    }

    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('إتمام مهمة التعقيب', style: TextStyle(color: AppTheme.primaryGold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'سيتم إرسال إشعار للمحامي بأن المهمة اكتملت وبانتظار اعتماده.',
              style: TextStyle(color: AppTheme.textGrey, height: 1.4),
            ),
            AppTheme.gapHeightMedium,
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'ملاحظات ختامية اختيارية'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إتمام وإشعار المحامي')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _completingTask = true);
    final prov2 = context.read<LegalProvider>();
    prov2.setActor(context.read<AuthProvider>().userModel?.uid ?? '');
    final ok = await prov2.completeExpeditingTask(
      taskId: widget.task.id,
      notes: notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _completingTask = false);
    if (ok) {
      setState(() => _taskStatus = 2);
      _snack('✅ تم إتمام المهمة وإشعار المحامي');
      // 2026-08-14: كان يبقى في التفاصيل بلا إشارة أن عمله انتهى — يعود
      // للقائمة بعد لحظة ليرى المهمة انتقلت إلى «بانتظار المراجعة».
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } else {
      _snack(context.read<LegalProvider>().error ?? 'فشل إتمام المهمة');
    }
  }

  void _showEditDialog(ChecklistItemModel item, {bool forceDone = false}) {
    final inputCtrl = TextEditingController(text: item.inputValue);
    final notesCtrl = TextEditingController(text: item.notes);
    int selectedSts = forceDone ? 2 : item.status;
    String attachmentBase64 = '';
    String attachmentName = '';
    final existingImage = item.attachmentSignedUrl.isNotEmpty
        ? item.attachmentSignedUrl
        : (item.attachmentUrl.startsWith('http') ? item.attachmentUrl : '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: Text(item.title, style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: AppTheme.paddingAllMedium,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGold.withOpacity(0.08),
                    borderRadius: AppTheme.radiusMedium,
                    border: Border.all(color: AppTheme.primaryGold.withOpacity(0.22)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('عدد النسخ المطلوبة: ${item.requiredCopies}', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody)),
                    if (item.lawyerInstructions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('تعليمات المحامي: ${item.lawyerInstructions}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.35)),
                    ],
                    if (item.revisionNotes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('طلب إعادة من المحامي: ${item.revisionNotes}', style: const TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall, height: 1.35)),
                    ],
                  ]),
                ),
                AppTheme.gapHeightMedium,
                DropdownButtonFormField<int>(
                  value: selectedSts,
                  dropdownColor: AppTheme.surfaceBlack,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(labelText: 'حالة الاستخراج'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('مطلوب')),
                    DropdownMenuItem(value: 1, child: Text('قيد الاستخراج ميدانياً')),
                    DropdownMenuItem(value: 2, child: Text('تم الاستخراج والرفع ✅')),
                    DropdownMenuItem(value: 3, child: Text('عائق إداري / نقص أوراق ⚠️')),
                  ],
                  onChanged: (v) => setDlg(() => selectedSts = v ?? 0),
                ),
                AppTheme.gapHeightMedium,
                TextField(
                  controller: inputCtrl,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(labelText: 'رقم العقار / رقم السيارة / الصحيفة'),
                ),
                AppTheme.gapHeightMedium,
                Container(
                  width: double.infinity,
                  padding: AppTheme.paddingAllMedium,
                  decoration: BoxDecoration(
                    color: AppTheme.scaffoldBackground,
                    borderRadius: AppTheme.radiusMedium,
                    border: Border.all(color: AppTheme.primaryGold.withOpacity(0.22)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('صورة السند / الوثيقة المستخرجة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody)),
                    AppTheme.gapHeightSmall,
                    if (attachmentBase64.isNotEmpty)
                      Text('تم اختيار صورة: $attachmentName', style: const TextStyle(color: AppTheme.successGreen, fontSize: AppTheme.fontSizeSmall))
                    else if (existingImage.isNotEmpty)
                      ClipRRect(
                        borderRadius: AppTheme.radiusSmall,
                        child: Image.network(existingImage, height: 130, width: double.infinity, fit: BoxFit.cover),
                      )
                    else
                      const Text('لم يتم إرفاق صورة بعد', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                    AppTheme.gapHeightSmall,
                    // 📷 2026-08-14: كان المعرض الخيار الوحيد — والمعقّب ميداني
                    // في الدوائر الحكومية: يستخرج السند فيريد تصويره ورفعه فوراً.
                    // كان مضطراً للخروج للكاميرا ثم العودة والبحث في المعرض.
                    Row(children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final file = await ImagePicker().pickImage(
                                source: ImageSource.camera, imageQuality: 82, maxWidth: 1600);
                            if (file == null) return;
                            final bytes = await file.readAsBytes();
                            setDlg(() {
                              attachmentBase64 = base64Encode(bytes);
                              attachmentName = file.name;
                            });
                          },
                          icon: const Icon(Icons.photo_camera, color: Colors.black, size: 18),
                          label: const Text('تصوير السند',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapWidthSmall,
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final file = await ImagePicker().pickImage(
                                source: ImageSource.gallery, imageQuality: 82, maxWidth: 1600);
                            if (file == null) return;
                            final bytes = await file.readAsBytes();
                            setDlg(() {
                              attachmentBase64 = base64Encode(bytes);
                              attachmentName = file.name;
                            });
                          },
                          icon: const Icon(Icons.image_search, color: AppTheme.primaryGold, size: 18),
                          label: const Text('من المعرض',
                              style: TextStyle(color: AppTheme.primaryGold, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primaryGold)),
                        ),
                      ),
                    ]),
                  ]),
                ),
                AppTheme.gapHeightMedium,
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(labelText: 'ملاحظات المعقب الميدانية'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey))),
            ElevatedButton(
              onPressed: () {
                if (selectedSts == 2 && existingImage.isEmpty && attachmentBase64.isEmpty) {
                  AppTheme.showSnackBar(context, const SnackBar(content: Text('يجب إرفاق صورة السند قبل تعليمه كمكتمل')));
                  return;
                }
                Navigator.pop(ctx);
                _updateItem(
                  item,
                  selectedSts,
                  inputCtrl.text.trim(),
                  item.attachmentUrl,
                  notesCtrl.text.trim(),
                  attachmentBase64: attachmentBase64,
                );
              },
              child: const Text('حفظ الإنجاز'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: Text(widget.task.itemType == 0 ? 'مهمة استخراج ثبوتيات عقار 🏠' : 'مهمة استخراج ثبوتيات مركبة 🚗'),
        backgroundColor: AppTheme.scaffoldBackground,
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.task.itemType == 0)
              Container(
                padding: AppTheme.paddingAllLarge,
                decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold)),
                child: Row(
                  children: [
                    const Icon(Icons.home, color: AppTheme.primaryGold),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: Text('رقم العقار: ${widget.task.targetPropertyNum.isEmpty ? "غير محدد" : widget.task.targetPropertyNum} | المنطقة العقارية: ${widget.task.targetZone.isEmpty ? "غير محددة" : widget.task.targetZone}', style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody)),
                    ),
                  ],
                ),
              ),
            // 📝 2026-08-14: تعليمات المحامي العامة (lawyer_notes) كانت مخزّنة
            // ولا تُعرض إطلاقاً — فيفوت المعقّب سياق المهمة («عاجل: العميل
            // ينتظر لإتمام صفقة») ويؤجلها ظناً أنها عادية.
            if (widget.task.lawyerNotes.trim().isNotEmpty) ...[
              AppTheme.gapHeightLarge,
              Container(
                width: double.infinity,
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.infoBlue.withOpacity(0.10),
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(color: AppTheme.infoBlue.withOpacity(0.45)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.sticky_note_2_outlined, color: AppTheme.infoBlue, size: 20),
                  AppTheme.gapWidthSmall,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('تعليمات المحامي',
                          style: TextStyle(color: AppTheme.infoBlue, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody)),
                      const SizedBox(height: 3),
                      Text(widget.task.lawyerNotes,
                          style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody, height: 1.5)),
                    ]),
                  ),
                ]),
              ),
            ],
            AppTheme.gapHeightLarge,
            const Text('📋 قائمة الوثائق الرسمية المطلوب استخراجها ميدانياً:', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightMedium,
            ..._items.map((item) {
              final isDone = item.status == 2;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: AppTheme.paddingAllLarge,
                decoration: BoxDecoration(
                  color: isDone ? AppTheme.successGreen.withOpacity(0.1) : AppTheme.surfaceBlack,
                  borderRadius: AppTheme.radiusLarge,
                  border: Border.all(color: isDone ? AppTheme.successGreen : Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: isDone ? AppTheme.successGreen : AppTheme.primaryGold),
                        AppTheme.gapWidthSmall,
                        Expanded(child: Text(item.title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 15))),
                        IconButton(icon: const Icon(Icons.edit, color: AppTheme.primaryGold), onPressed: () => _showEditDialog(item)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('المطلوب من المحامي: ${item.requiredCopies} نسخة', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.w600)),
                    if (item.lawyerInstructions.isNotEmpty) ...[
                      AppTheme.gapHeightXS,
                      Text('تعليمات المحامي: ${item.lawyerInstructions}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.35)),
                    ],
                    if (item.inputValue.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('البيانات المُدخلة: ${item.inputValue}', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.w600)),
                    ],
                    if (item.revisionNotes.isNotEmpty) ...[
                      AppTheme.gapHeightXS,
                      Text('طلب إعادة من المحامي: ${item.revisionNotes}', style: const TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall, height: 1.35)),
                    ],
                    if (item.notes.isNotEmpty) ...[
                      AppTheme.gapHeightXS,
                      Text('ملاحظات: ${item.notes}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                    ],
                    if (item.attachmentSignedUrl.isNotEmpty || item.attachmentUrl.startsWith('http')) ...[
                      AppTheme.gapHeightSmall,
                      ClipRRect(
                        borderRadius: AppTheme.radiusMedium,
                        child: Image.network(
                          item.attachmentSignedUrl.isNotEmpty ? item.attachmentSignedUrl : item.attachmentUrl,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                    AppTheme.gapHeightMedium,
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isDone ? null : () => _showEditDialog(item, forceDone: true),
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('تم الاستخراج ✔️', style: TextStyle(fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successGreen,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        AppTheme.gapWidthSmall,
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showEditDialog(item),
                            icon: const Icon(Icons.edit_note, size: 16, color: AppTheme.primaryGold),
                            label: const Text('البيانات والمرفق ✏️', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primaryGold),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
            AppTheme.gapHeightSmall,
            Container(
              width: double.infinity,
              padding: AppTheme.paddingAllLarge,
              decoration: BoxDecoration(
                color: _taskStatus >= 2 ? AppTheme.successGreen.withOpacity(0.1) : AppTheme.surfaceBlack,
                borderRadius: AppTheme.radiusLarge,
                border: Border.all(color: _taskStatus >= 2 ? AppTheme.successGreen : AppTheme.primaryGold.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _taskStatus >= 3
                        ? 'تم اعتماد المهمة من المحامي ✅'
                        : _taskStatus == 2
                            ? 'تم إرسال الإنجاز للمحامي — بانتظار الاعتماد ✅'
                            : _allItemsDone
                                ? 'كل البنود مكتملة — يمكنك الآن إتمام المهمة وإشعار المحامي'
                                : 'أكمل كل البنود أولاً حتى يظهر زر إتمام المهمة',
                    style: TextStyle(
                      color: _taskStatus >= 2 || _allItemsDone ? AppTheme.successGreen : AppTheme.textGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody,
                    ),
                  ),
                  if (_taskStatus < 2) ...[
                    AppTheme.gapHeightMedium,
                    ElevatedButton.icon(
                      onPressed: (!_allItemsDone || _completingTask) ? null : _completeTask,
                      icon: _completingTask
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.deepBlack))
                          : const Icon(Icons.done_all, color: AppTheme.deepBlack),
                      label: Text(
                        _completingTask ? 'جاري الإرسال...' : 'إتمام المهمة وإشعار المحامي',
                        style: const TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
