import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../models/user_model.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/e2e.dart';
import '../../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _staffStats;
  bool _loadingStats = false;
  int _activeBlock = 0;
  int _signupMethod = 0;

  final _loginUserCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  final _signupPhoneCtrl = TextEditingController();
  final _signupEmailCtrl = TextEditingController();

  bool _isPassObscure = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadStaffStats();
  }

  @override
  void dispose() {
    _loginUserCtrl.dispose();
    _loginPassCtrl.dispose();
    _signupPhoneCtrl.dispose();
    _signupEmailCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  Future<void> _loadStaffStats() async {
    final auth = context.read<AuthProvider>();
    if (auth.userModel == null || !auth.userModel!.isInternal) return;
    setState(() => _loadingStats = true);
    try {
      final token = await AuthService().getStaffSessionToken();
      final response = await SupabaseService().invokeFunction('admin-dashboard', body: {
        'action': 'staff_stats',
        'user_uid': auth.userModel!.uid,
        'staff_session_token': token,
      });
      final res = response.data != null && response.data['success'] == true ? response.data['stats'] : null;
      if (mounted) setState(() { _staffStats = res is Map ? Map<String, dynamic>.from(res) : null; _loadingStats = false; });
    } catch (_) { if (mounted) setState(() => _loadingStats = false); }
  }

    Future<void> _handleLogin() async {
    final user = _loginUserCtrl.text.trim();
    final pass = _loginPassCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _snack('يرجى إدخال كافة البيانات');
      return;
    }
    setState(() => _isBusy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithPassword(user, pass);
    if (mounted) setState(() => _isBusy = false);
    if (!ok) {
      _snack('فشل تسجيل الدخول، تأكد من بياناتك');
    } else {
      // 🚀 توجيه فوري - لا ننتظر rebuild كي لا تظهر شاشة الحساب للحظة
      if (mounted) {
        if (auth.isLawyer) {
          context.go('/lawyer/dashboard');
        } else if (auth.isExpediter) {
          context.go('/expediter/tasks');
        } else if (auth.isSenior) {
          context.go('/admin/dashboard');
        } else if (auth.isEmployee) {
          context.go('/employee/home');
        } else if (auth.isSupervisor) {
          context.go('/executor/tasks');
        } else if (auth.isPhotographer) {
          context.go('/photographer/tasks');
        } else if (auth.isBroker) {
          context.go('/broker/dashboard');
        } else {
          context.go('/user/home');
        }
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final phone = _loginUserCtrl.text.trim();
    if (phone.length != 10 || !phone.startsWith('09')) {
      _snack('أدخل رقم هاتفك في خانة المستخدم أولاً');
      return;
    }
    setState(() => _isBusy = true);
    final ok = await context.read<AuthProvider>().sendSMSOTP(phone);
    if (mounted) {
      setState(() => _isBusy = false);
    }
    if (ok) {
      _snack('تم إرسال كود الاستعادة SMS');
      context.push('/otp');
    } else {
      _snack('فشل إرسال رسالة الاستعادة');
    }
  }

  Future<void> _handleSignupPhone() async {
    final phone = _signupPhoneCtrl.text.trim();
    if (phone.length != 10 || !phone.startsWith('09')) {
      _snack('أدخل رقم هاتف صحيح');
      return;
    }
    setState(() => _isBusy = true);
    final ok = await context.read<AuthProvider>().sendSMSOTP(phone);
    if (mounted) {
      setState(() => _isBusy = false);
    }
    if (ok) {
      _snack('تم إرسال رمز التفعيل SMS');
      context.push('/otp');
    } else {
      _snack('فشل إرسال SMS التفعيل');
    }
  }

  Future<void> _handleSignupEmail() async {
    final email = _signupEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('أدخل بريداً صحيحاً');
      return;
    }
    setState(() => _isBusy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendEmailMagicLink(email);
    if (mounted) {
      setState(() => _isBusy = false);
    }
    if (ok) {
      _snack('تم إرسال الرابط — إذا لم تجده خلال دقيقة افحص البريد غير المرغوب فيه');
      context.push('/check-email');
    } else {
      _snack(auth.lastError ?? 'فشل إرسال رابط الإيميل');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.userModel;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: _buildVisitorUI(),
        bottomNavigationBar: const CustomBottomNavBar(currentIndex: 5),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(user)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
              if (user.isInternal) _buildStaffStats(user)
                else ...[_buildUserStats(user), AppTheme.gapHeightLarge, _buildActivityStats(user)],
                AppTheme.gapHeightXL,
                if (!user.isInternal) _buildMenuSection(user),
                AppTheme.gapHeightXL,
                _buildLogoutButton(auth),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 5),
    );
  }

  Widget _buildVisitorUI() {
    final sz = MediaQuery.sizeOf(context);
    final logoSize = (sz.shortestSide * 0.9).clamp(300.0, 520.0);

    return Container(
      width: double.infinity,
      color: AppTheme.scaffoldBackground,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              AppTheme.gapHeightSmall,
              _buildFadedAccountLogo(logoSize),
              AppTheme.gapHeightSmall,
              Text('المكتب العقاري الإلكتروني', style: GoogleFonts.cairo(color: AppTheme.primaryGold, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 50),

              _buildBlock(
                id: 2, title: 'تسجيل الدخول', icon: Icons.login_rounded, isGold: false,
                child: Column(children: [
                  _buildInput(_loginUserCtrl, 'اسم المستخدم أو رقم الهاتف', Icons.person_outline, e2eId: 'e2e_login_username'),
                  AppTheme.gapHeightMedium,
                  _buildInput(_loginPassCtrl, 'كلمة المرور', Icons.lock_outline, isPass: true, obscure: _isPassObscure, onToggle: () => setState(() => _isPassObscure = !_isPassObscure), e2eId: 'e2e_login_password'),
                  AppTheme.gapHeightXL,
                  _buildBigBtn(label: 'دخول', onTap: _handleLogin, e2eId: 'e2e_login_button'),
                  AppTheme.gapHeightSmall,
                  TextButton(onPressed: _handleForgotPassword, child: const Text('هل نسيت كلمة المرور؟ استعادة بـ SMS', style: TextStyle(color: AppTheme.primaryGold, decoration: TextDecoration.underline, fontSize: AppTheme.fontSizeBody))),
                ]),
              ),

              AppTheme.gapHeightLarge,

              _buildBlock(
                id: 1, title: 'تسجيل حساب جديد', icon: Icons.person_add_alt_1_outlined, isGold: true,
                child: Column(children: [
                  _buildInnerOption(id: 1, title: 'تسجيل عن طريق رقم الهاتف', icon: Icons.phone_android, child: Column(children: [
                    const Text('سيصلك رمز تفعيل برسالة نصية SMS', style: TextStyle(color: Colors.black87, fontSize: AppTheme.fontSizeCaption)),
                    AppTheme.gapHeightMedium,
                    _buildInput(_signupPhoneCtrl, '09XXXXXXXX', Icons.phone_iphone, dark: true),
                    AppTheme.gapHeightMedium,
                    _buildBigBtn(label: 'إرسال رمز التفعيل SMS', onTap: _handleSignupPhone, dark: true),
                  ])),
                  AppTheme.gapHeightMedium,
                  _buildInnerOption(id: 2, title: 'تسجيل عن طريق الإيميل', icon: Icons.alternate_email, child: Column(children: [
                    const Text(
                      'سيصلك رابط تفعيل إلى بريدك الإلكتروني. إذا لم يظهر في الوارد خلال دقيقة افحص Spam / البريد غير المرغوب فيه.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black87, fontSize: AppTheme.fontSizeCaption, height: 1.4),
                    ),
                    AppTheme.gapHeightMedium,
                    _buildInput(_signupEmailCtrl, 'example@mail.com', Icons.email_outlined, dark: true),
                    AppTheme.gapHeightMedium,
                    _buildBigBtn(label: 'إرسال رابط التفعيل', onTap: _handleSignupEmail, dark: true),
                  ])),
                ]),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFadedAccountLogo(double logoSize) {
    final boxSize = (logoSize * 0.72).clamp(250.0, 390.0);
    final radius = BorderRadius.circular(34);

    return Hero(
      tag: 'logo',
      child: Container(
        width: boxSize,
        height: boxSize,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGold.withOpacity(0.18),
              blurRadius: 70,
              spreadRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: AppTheme.scaffoldBackground),
              Image.asset('assets/images/logo_app.png', fit: BoxFit.cover),
              // فيد ناعم يخفي حواف مربع الشعار الأسود ويدمجه مع الخلفية النهارية
              // بدون قص النص العربي داخل الشعار.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.86,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      AppTheme.scaffoldBackground.withOpacity(0.16),
                      AppTheme.scaffoldBackground.withOpacity(0.78),
                    ],
                    stops: const [0.0, 0.68, 0.84, 1.0],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: AppTheme.primaryGold.withOpacity(0.34),
                    width: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlock({required int id, required String title, required IconData icon, required bool isGold, required Widget child}) {
    final isOpen = _activeBlock == id;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isGold ? AppTheme.primaryGold : AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusXXL,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.5), width: 2),
      ),
      child: Column(children: [
        E2E(
          id: id == 2 ? 'e2e_profile_login_section' : 'e2e_profile_signup_section',
          button: true,
          child: InkWell(
          onTap: () => setState(() { _activeBlock = isOpen ? 0 : id; if (id == 1) _signupMethod = 0; }),
          borderRadius: AppTheme.radiusXXL,
          child: Padding(padding: AppTheme.paddingAllXL, child: Row(children: [
            Icon(icon, color: isOpen && isGold ? Colors.black : (isGold ? Colors.black : AppTheme.primaryGold), size: 28),
            AppTheme.gapWidthLarge,
            Text(title, style: TextStyle(color: isGold ? Colors.black : AppTheme.textWhite, fontSize: AppTheme.fontSizeTitle, fontWeight: FontWeight.w900)),
            const Spacer(),
            Icon(isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: isGold ? Colors.black : AppTheme.textGrey),
          ])),
          ),
        ),
        if (isOpen) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), child: child),
      ]),
    );
  }

  Widget _buildInnerOption({required int id, required String title, required IconData icon, required Widget child}) {
    final sel = _signupMethod == id;
    return Container(
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: AppTheme.radiusLarge),
      child: Column(children: [
        ListTile(
          onTap: () => setState(() => _signupMethod = sel ? 0 : id),
          leading: Icon(icon, color: Colors.black87),
          title: Text(title, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium)),
          trailing: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: Colors.black87),
        ),
        if (sel) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), child: child),
      ]),
    );
  }

  Widget _buildInput(TextEditingController c, String h, IconData i, {bool isPass = false, bool? obscure, VoidCallback? onToggle, bool dark = false, String? e2eId}) {
    final field = TextField(
      controller: c, obscureText: obscure ?? false, textAlign: TextAlign.left,
      style: TextStyle(color: dark ? Colors.black : AppTheme.textWhite, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        hintText: h, prefixIcon: Icon(i, color: dark ? Colors.black45 : AppTheme.primaryGold),
        fillColor: dark ? Colors.white.withOpacity(0.8) : AppTheme.surfaceBlack,
        suffixIcon: isPass ? IconButton(icon: Icon(obscure! ? Icons.visibility_off : Icons.visibility, color: AppTheme.textGrey), onPressed: onToggle) : null,
      ),
    );
    return e2eId == null ? field : E2E(id: e2eId, child: field);
  }

  Widget _buildBigBtn({required String label, required VoidCallback? onTap, bool dark = false, String? e2eId}) {
    final button = SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
      onPressed: _isBusy ? null : onTap,
      style: ElevatedButton.styleFrom(backgroundColor: dark ? Colors.black : Colors.white, foregroundColor: dark ? Colors.white : Colors.black, shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge)),
      child: _isBusy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: AppTheme.fontSizeSubtitle)),
    ));
    return e2eId == null ? button : E2E(id: e2eId, button: true, child: button);
  }

  Widget _buildHeader(UserModel user) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 24, left: 20, right: 20),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppTheme.primaryGold.withOpacity(0.2), AppTheme.deepBlack])),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(user.isInternal ? 'الملف الوظيفي' : 'حسابي', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 22, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.settings_outlined, color: AppTheme.primaryGold), onPressed: () => context.push('/user/settings')),
        ]),
        AppTheme.gapHeightLarge,
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [AppTheme.primaryGold, AppTheme.lightGold]), boxShadow: [BoxShadow(color: AppTheme.primaryGold.withOpacity(0.25), blurRadius: 20, spreadRadius: 2)]),
          child: Container(margin: const EdgeInsets.all(3), decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.surfaceBlack), child: Center(child: Text(user.nm.isNotEmpty ? user.nm[0] : '؟', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 36, fontWeight: FontWeight.bold)))),
        ),
        AppTheme.gapHeightMedium,
        Text(user.nm.isNotEmpty ? user.nm : 'مستخدم جديد', style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeHeadline, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (user.isInternal) ...[
          Text(user.roleName, style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeMedium, fontWeight: FontWeight.w600)),
          AppTheme.gapHeightXS,
          if (user.sid.isNotEmpty) Text('الرقم الوطني: ${user.sid}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
          if (user.ad.isNotEmpty) Text('العنوان: ${user.ad}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
        ] else if (user.usr != null)
          Text('@${user.usr}', style: TextStyle(color: AppTheme.textGrey.withOpacity(0.8), fontSize: AppTheme.fontSizeMedium)),
        AppTheme.gapHeightMedium,
        if (!user.isInternal)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _buildChip(user.roleName, AppTheme.primaryGold.withOpacity(0.15), AppTheme.primaryGold),
            AppTheme.gapWidthSmall,
            _buildChip(user.badgeName, Colors.white.withOpacity(0.08), AppTheme.textWhite),
            if (user.isVerifiedOfficial) ...[AppTheme.gapWidthSmall, _buildChip('✓ موثق', AppTheme.successGreen.withOpacity(0.15), AppTheme.successGreen)],
          ]),
      ]),
    );
  }

  Widget _buildChip(String t, Color b, Color f) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: b, borderRadius: AppTheme.radiusLarge, border: Border.all(color: f.withOpacity(0.3))), child: Text(t, style: TextStyle(color: f, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.w600)));
  Widget _buildUserStats(UserModel u) => Row(children: [Expanded(child: _buildStatTile(icon: Icons.star_rounded, value: '${u.pt}', label: 'النقاط', color: const Color(0xFFFFD700))), AppTheme.gapWidthMedium, Expanded(child: _buildStatTile(icon: Icons.local_fire_department_rounded, value: '${u.strk}', label: 'أيام متتالية', color: const Color(0xFFFF6B35)))]);
  Widget _buildStatTile({required IconData icon, required String value, required String label, required Color color}) => Container(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12), decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: color.withOpacity(0.2))), child: Row(children: [Container(padding: AppTheme.paddingAllSmall, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: AppTheme.radiusMedium), child: Icon(icon, color: color, size: 22)), AppTheme.gapWidthSmall, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeTitle, fontWeight: FontWeight.bold)), Text(label, style: TextStyle(color: AppTheme.textGrey.withOpacity(0.7), fontSize: AppTheme.fontSizeCaption))])]));
  Widget _buildActivityStats(UserModel u) => Container(padding: AppTheme.paddingAllLarge, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.analytics_outlined, color: AppTheme.primaryGold.withOpacity(0.8), size: 18), AppTheme.gapWidthSmall, const Text('إحصائيات النشاط', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeMedium, fontWeight: FontWeight.w600))]), AppTheme.gapHeightMedium, Row(children: [_buildMiniStat('عروض', u.stats['off'] ?? 0, Icons.home_work_outlined), _buildMiniStat('طلبات', u.stats['req'] ?? 0, Icons.assignment_outlined), _buildMiniStat('مواعيد', u.stats['app'] ?? 0, Icons.calendar_today_outlined), _buildMiniStat('صفقات', u.stats['dl'] ?? 0, Icons.handshake_outlined)])]));
  Widget _buildMiniStat(String l, int c, IconData i) => Expanded(child: Column(children: [Icon(i, color: AppTheme.primaryGold.withOpacity(0.7), size: 20), const SizedBox(height: 6), Text('$c', style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold)), AppTheme.gapHeightXXS, Text(l, style: TextStyle(color: AppTheme.textGrey.withOpacity(0.6), fontSize: AppTheme.fontSizeXS))]));
  Widget _buildStaffStats(UserModel user) {
    if (_loadingStats) {
      return const Center(
        child: Padding(
          padding: AppTheme.paddingAllXL,
          child: CircularProgressIndicator(color: AppTheme.primaryGold),
        ),
      );
    }
    if (_staffStats == null) {
      return const SizedBox.shrink();
    }

    List<_StaffStatItem> items = [];
    if (user.isPhotographer) {
      items = [
        _StaffStatItem(Icons.check_circle_outline, 'مهام مكتملة',
            _staffStats!['completed_tasks'] ?? 0, AppTheme.successGreen),
      ];
    } else if (user.isSupervisor) {
      items = [
        _StaffStatItem(Icons.check_circle_outline, 'زيارات منفذة',
            _staffStats!['completed_visits'] ?? 0, AppTheme.successGreen),
      ];
    } else if (user.isEmployee) {
      items = [
        _StaffStatItem(Icons.rate_review_outlined, 'عروض مراجَعة',
            _staffStats!['reviewed_offers'] ?? 0, AppTheme.infoBlue),
      ];
    } else if (user.isSenior || user.isManager) {
      items = [
        _StaffStatItem(Icons.handshake_outlined, 'صفقات',
            _staffStats!['total_deals'] ?? 0, AppTheme.successGreen),
        _StaffStatItem(Icons.payments_outlined, 'مدفوعات',
            _staffStats!['approved_payments'] ?? 0, AppTheme.infoBlue),
        _StaffStatItem(Icons.verified_user_outlined, 'موثقون',
            _staffStats!['verified_users'] ?? 0, Colors.teal),
      ];
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map((it) => Container(
                width: (MediaQuery.of(context).size.width - 60) / 2,
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: it.color.withOpacity(0.1),
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(color: it.color.withOpacity(0.2)),
                ),
                child: Row(children: [
                  Icon(it.icon, color: it.color, size: 18),
                  AppTheme.gapWidthSmall,
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${it.value}',
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: AppTheme.fontSizeSubtitle,
                            fontWeight: FontWeight.bold)),
                    Text(it.label,
                        style: const TextStyle(
                            color: AppTheme.textGrey, fontSize: AppTheme.fontSizeXS)),
                  ]),
                ]),
              ))
          .toList(),
    );
  }

  Widget _buildMenuSection(UserModel u) => Column(children: [
        _buildMenuItem(
            i: Icons.person_outline,
            t: u.isInternal ? 'بياناتي الوظيفية' : 'معلومات الحساب',
            s: u.isInternal
                ? 'بيانات التعيين والتحقق الوظيفي ✅'
                : 'معلوماتك الشخصية والتوثيق',
            o: () => context.push('/user/account-info')),
        _buildMenuItem(
            i: Icons.star_outline,
            t: 'تقييماتي المستلمة',
            s: 'شاهد تقييمات العملاء لك',
            o: () => context.push('/user/my-ratings')),
        // 🎁 BUG-003 (أُصلح 2026-08-14): شاشة الإحالة كانت **مبنية بالكامل
        // ومسجَّلة بالراوتر بلا أي زر يفتحها** — ميزة مدفونة بالكامل.
        // (تحقُّق: صفر مرجع لـ'/user/referral' خارج ملف الراوتر.)
        if (!u.isInternal)
          _buildMenuItem(
              i: Icons.card_giftcard_outlined,
              t: 'ادعُ أصدقاءك',
              s: 'شارك كود الدعوة واكسب نقاطاً',
              o: () => context.push('/user/referral')),
        // 🤝 الوسيط: لوحة التحكم أو الانضمام
        if (u.isBroker)
          _buildMenuItem(
              i: Icons.handshake_outlined,
              t: 'لوحة الوسيط',
              s: 'عروضي، صفقاتي، مواعيدي، إحصائياتي',
              o: () => context.go('/broker/dashboard'))
        else if (!u.isInternal)
          _buildMenuItem(
              i: Icons.handshake_outlined,
              t: 'انضم كوسيط',
              s: u.isVerifiedOfficial
                  ? '📋 قدّم طلبك — هويتك موثّقة ✅'
                  : 'قدّم طلب وساطة عقارية — يشترط توثيق الهوية',
              o: () => context.push('/user/become-broker')),
        if (u.isInternal)
          _buildMenuItem(
              i: u.isLawyer
                  ? Icons.gavel_outlined
                  : u.isExpediter
                      ? Icons.assignment_turned_in_outlined
                      : Icons.dashboard_outlined,
              t: u.isLawyer
                  ? 'لوحة المحامي'
                  : u.isExpediter
                      ? 'مهام التعقيب'
                      : 'لوحة التحكم الإدارية',
              s: u.isLawyer
                  ? 'المواعيد والمهام القانونية'
                  : u.isExpediter
                      ? 'متابعة مهام التعقيب المستلمة'
                      : 'الانتقال لواجهة العمليات',
              o: () {
                if (u.isLawyer) {
                  context.go('/lawyer/dashboard');
                } else if (u.isExpediter) {
                  context.go('/expediter/tasks');
                } else if (u.isPhotographer) {
                  context.go('/photographer/tasks');
                } else if (u.isSupervisor) {
                  context.go('/executor/tasks');
                } else if (u.isEmployee) {
                  context.go('/employee/home');
                } else {
                  context.go('/admin/dashboard');
                }
              }),
      ]);
  Widget _buildMenuItem({required IconData i, required String t, required String s, required VoidCallback o}) => ListTile(onTap: o, leading: Icon(i, color: AppTheme.primaryGold), title: Text(t, style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium, fontWeight: FontWeight.bold)), subtitle: Text(s, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)), trailing: const Icon(Icons.chevron_right, color: AppTheme.textGrey, size: 18));

  Widget _buildLogoutButton(AuthProvider a) => OutlinedButton.icon(onPressed: () { a.logout(); context.go('/user/profile'); }, icon: const Icon(Icons.logout, color: AppTheme.errorRed), label: const Text('تسجيل الخروج', style: TextStyle(color: AppTheme.errorRed)), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.errorRed), minimumSize: const Size(double.infinity, 50)));
}

class _StaffStatItem { final IconData icon; final String label; final int value; final Color color; _StaffStatItem(this.icon, this.label, this.value, this.color); }
