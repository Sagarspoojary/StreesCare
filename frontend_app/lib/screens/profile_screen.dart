import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  // ── Controllers ───────────────────────────────────────────────────────────
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── State ─────────────────────────────────────────────────────────────────
  String _email     = "";
  String _createdAt = "N/A";
  bool   _loading   = true;
  bool   _notifEnabled    = true;
  bool   _biometricEnabled = false;
  bool   _pinEnabled       = false;
  
  // -- Dynamic Profile Stats Variables --
  int _totalSessions = 24;
  int _streakDays = 5;
  String _latestMood = "Calm";
  
  double _stressFraction = 0.28;
  double _focusFraction = 0.72;
  double _calmFraction = 0.65;
  int _wellnessScore = 78;
  String _wellnessChange = "↑ Perfect";

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _bg     = Color(0xFF0D1117);
  static const _card   = Color(0xFF161B22);
  static const _blue   = Color(0xFF4A90E2);
  static const _teal   = Color(0xFF00C9A7);
  static const _purple = Color(0xFF9B59B6);
  static const _orange = Color(0xFFFF8C42);

  final _localAuth = LocalAuthentication();
  final _storage   = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadUserData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _email = user.email ?? "";
      final pin = await _storage.read(key: "app_pin");
      try {
        final doc = await FirebaseFirestore.instance
            .collection("users").doc(user.uid).get();
        if (doc.exists) {
          final d = doc.data()!;
          _nameCtrl.text = d["full_name"] ?? "";
          _phoneCtrl.text = d["phone_number"] ?? "";
          if (d["createdAt"] != null) {
            final dt = (d["createdAt"] as Timestamp).toDate();
            _createdAt = "${dt.day}/${dt.month}/${dt.year}";
          }
        }
      } catch (_) {}
      
      // Calculate dynamic active streak using SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
        List<String> activeDates = prefs.getStringList("active_dates") ?? [];
        if (!activeDates.contains(todayStr)) {
          activeDates.add(todayStr);
          await prefs.setStringList("active_dates", activeDates);
        }
        
        activeDates.sort((a, b) => b.compareTo(a));
        int streak = 0;
        DateTime current = DateTime.now();
        for (int i = 0; i < activeDates.length; i++) {
          final dateStr = activeDates[i];
          final parts = dateStr.split('-');
          final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          
          final diff = current.difference(date).inDays;
          if (diff == 0 || diff == 1) {
            streak++;
            current = date;
          } else {
            break;
          }
        }
        _streakDays = streak > 0 ? streak : 1;
      } catch (_) {}

      // Query Chat History to calculate real statistics
      try {
        final rawMessages = await ChatService.getChatHistory();
        if (rawMessages.isNotEmpty) {
          final Set<String> uniqueSessions = {};
          double totalStress = 0.0;
          int stressCount = 0;
          String mood = "Calm";
          
          for (var m in rawMessages) {
            if (m is! Map<String, dynamic>) continue;
            final String sessId = m["session_id"]?.toString() ?? "default";
            uniqueSessions.add(sessId);
            
            final scoreVal = m["score"] ?? m["stress_score"];
            if (scoreVal != null) {
              final double parsedScore = double.tryParse(scoreVal.toString()) ?? 0.0;
              totalStress += parsedScore;
              stressCount++;
            }
            
            final emotion = m["emotion"];
            if (emotion != null && emotion.toString().isNotEmpty) {
              mood = emotion.toString();
            }
          }
          
          if (uniqueSessions.isNotEmpty) {
            _totalSessions = uniqueSessions.length;
          }
          
          if (stressCount > 0) {
            final double avgStress = totalStress / stressCount;
            _stressFraction = avgStress / 100.0;
            if (_stressFraction > 1.0) _stressFraction = 1.0;
            if (_stressFraction < 0.0) _stressFraction = 0.0;
            
            _focusFraction = 1.0 - (_stressFraction * 0.4);
            if (_focusFraction > 1.0) _focusFraction = 1.0;
            
            _calmFraction = 1.0 - _stressFraction;
            if (_calmFraction > 1.0) _calmFraction = 1.0;
            
            _wellnessScore = (100 - avgStress).toInt();
            if (_wellnessScore > 100) _wellnessScore = 100;
            if (_wellnessScore < 0) _wellnessScore = 0;
            
            _wellnessChange = _wellnessScore >= 85 
                ? "↑ Perfect" 
                : (_wellnessScore >= 70 ? "↑ Good" : "↑ Stable");
          }
          
          if (mood.isNotEmpty) {
            _latestMood = mood[0].toUpperCase() + mood.substring(1);
          }
        }
      } catch (e) {
        print("Error parsing live chat history for profile: $e");
      }

      if (mounted) setState(() { _pinEnabled = pin != null; _loading = false; });
    } else {
      if (mounted) setState(() => _loading = false);
    }
    _fadeCtrl.forward();
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection("users").doc(user.uid).update({
        "full_name": _nameCtrl.text.trim(),
        "phone_number": _phoneCtrl.text.trim(),
      });
      if (mounted) {
        setState(() {}); // 🌟 Force immediate UI re-build to refresh name & avatar initials!
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile saved!"), backgroundColor: _teal));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildAppBar(),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildStatsRow(),
                        const SizedBox(height: 24),
                        _buildWellnessScore(),
                        const SizedBox(height: 24),
                        _buildSectionTitle("⚙️  Settings"),
                        const SizedBox(height: 12),
                        _buildMenuItem(Icons.person_rounded,     "Account Settings",  _blue,   _showAccountSettings),
                        _buildMenuItem(Icons.notifications_rounded, "Notifications", _orange, _showNotificationsSettings),
                        _buildMenuItem(Icons.lock_rounded,       "Privacy & Security", _purple, _showPrivacySettings),
                        _buildMenuItem(Icons.headset_mic_rounded, "Help & Support",  _teal,   _showHelpSupport),
                        const SizedBox(height: 12),
                        _buildMenuItem(Icons.logout_rounded, "Sign Out", Colors.redAccent, _signOut),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────
  SliverAppBar _buildAppBar() => SliverAppBar(
    pinned: true,
    backgroundColor: _bg.withOpacity(0.8),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _blue),
      onPressed: () => Navigator.pop(context),
    ),
    title: const Text("My Profile",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    actions: [
      IconButton(
        icon: const Icon(Icons.edit_rounded, color: _blue),
        onPressed: _showAccountSettings,
      ),
    ],
  );

  // ── Profile Header ────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(24),
    decoration: _glassBox(),
    child: Column(children: [
      Stack(children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [_blue, _teal]),
            border: Border.all(color: _blue.withOpacity(0.4), width: 3),
            boxShadow: [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 20)],
          ),
          child: Center(
            child: Text(
              _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : "U",
              style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Positioned(
          bottom: 0, right: 0,
          child: GestureDetector(
            onTap: _showAccountSettings,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: _blue),
              child: const Icon(Icons.edit, color: Colors.white, size: 14),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Text(
        _nameCtrl.text.isNotEmpty ? _nameCtrl.text : "User",
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      const SizedBox(height: 4),
      Text(_email, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _teal.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _teal.withOpacity(0.3)),
        ),
        child: const Text("🌿 Wellness Journey Active",
            style: TextStyle(color: _teal, fontSize: 12)),
      ),
    ]),
  );

  // ── Stats Row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() => Row(children: [
    _buildStatCard("Sessions", "$_totalSessions", Icons.chat_bubble_rounded, _blue),
    const SizedBox(width: 12),
    _buildStatCard("Streak", "${_streakDays}d 🔥", Icons.local_fire_department_rounded, _orange),
    const SizedBox(width: 12),
    _buildStatCard("Mood", _latestMood, Icons.sentiment_satisfied_alt_rounded, _teal),
  ]);

  Widget _buildStatCard(String label, String value, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _glassBox(border: color.withOpacity(0.2)),
          child: Column(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
          ]),
        ),
      );

  // ── Wellness Score ────────────────────────────────────────────────────────
  Widget _buildWellnessScore() => Container(
    padding: const EdgeInsets.all(20),
    decoration: _glassBox(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("AI Wellness Score",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _buildRing("Stress", _stressFraction, Colors.redAccent),
              const SizedBox(width: 8),
              _buildRing("Focus", _focusFraction, _blue),
              const SizedBox(width: 8),
              _buildRing("Calm", _calmFraction, _teal),
            ],
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Overall", style: TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text("$_wellnessScore/100", style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_wellnessChange,
                      style: const TextStyle(color: _teal, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    ]),
  );

  Widget _buildRing(String label, double fraction, Color color) => Column(children: [
    SizedBox(
      width: 56, height: 56,
      child: CustomPaint(painter: _RingPainter(fraction, color)),
    ),
    const SizedBox(height: 6),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    Text("${(fraction * 100).toInt()}%",
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
  ]);

  // ── Section Title ─────────────────────────────────────────────────────────
  Widget _buildSectionTitle(String t) =>
      Text(t, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold));

  // ── Menu Item ─────────────────────────────────────────────────────────────
  Widget _buildMenuItem(IconData icon, String title, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: _glassBox(border: color.withOpacity(0.15)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(title, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.25), size: 14),
          ]),
        ),
      );

  // ── Glass Box Decoration ─────────────────────────────────────────────────
  BoxDecoration _glassBox({Color? border}) => BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: border ?? Colors.white.withOpacity(0.08)),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12)],
  );

  // ── Sign Out ──────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    await AuthService.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, "/signin", (_) => false);
  }

  // ── Modals (preserved from original) ────────────────────────────────────
  void _showAccountSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 24, right: 24, top: 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Account Settings",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _darkField(_nameCtrl, "Full Name"),
          const SizedBox(height: 12),
          _darkField(_phoneCtrl, "Phone Number", type: TextInputType.phone),
          const SizedBox(height: 12),
          _darkField(TextEditingController(text: _email), "Email", readOnly: true),
          const SizedBox(height: 8),
          Text("Joined: $_createdAt", style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () { _saveProfile(); Navigator.pop(ctx); },
              child: const Text("Save Changes", style: TextStyle(color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showNotificationsSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, set) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Notifications",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text("Enable Notifications", style: TextStyle(color: Colors.white)),
              subtitle: const Text("Daily wellness tips", style: TextStyle(color: Colors.white54)),
              value: _notifEnabled,
              activeColor: _teal,
              onChanged: (v) { set(() => _notifEnabled = v); setState(() => _notifEnabled = v); },
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }

  void _showPrivacySettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, set) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Privacy & Security",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text("Biometric Unlock", style: TextStyle(color: Colors.white)),
              subtitle: const Text("Fingerprint / Face ID", style: TextStyle(color: Colors.white54)),
              value: _biometricEnabled,
              activeColor: _teal,
              onChanged: (v) async {
                if (v) {
                  try {
                    final ok = await _localAuth.authenticate(
                        localizedReason: "Enable biometric unlock",
                        options: const AuthenticationOptions(biometricOnly: true));
                    set(() => _biometricEnabled = ok);
                    setState(() => _biometricEnabled = ok);
                  } catch (_) {
                    set(() => _biometricEnabled = false);
                  }
                } else {
                  set(() => _biometricEnabled = false);
                  setState(() => _biometricEnabled = false);
                }
              },
            ),
            SwitchListTile(
              title: const Text("PIN Lock", style: TextStyle(color: Colors.white)),
              subtitle: const Text("4-digit app PIN", style: TextStyle(color: Colors.white54)),
              value: _pinEnabled,
              activeColor: _purple,
              onChanged: (v) async {
                if (v) {
                  _showPinSetup(set);
                } else {
                  await _storage.delete(key: "app_pin");
                  set(() => _pinEnabled = false);
                  setState(() => _pinEnabled = false);
                }
              },
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }

  void _showPinSetup(StateSetter setModalState) {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    bool confirm = false;
    String first = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (bCtx) => StatefulBuilder(
        builder: (_, ps) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(bCtx).viewInsets.bottom + 24,
              left: 24, right: 24, top: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(confirm ? "Confirm PIN" : "Set PIN",
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _darkField(confirm ? c2 : c1, confirm ? "Confirm 4-digit PIN" : "Enter 4-digit PIN",
                type: TextInputType.number, obscure: true, maxLen: 4),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final pin = confirm ? c2.text.trim() : c1.text.trim();
                  if (pin.length != 4) return;
                  if (!confirm) { ps(() { confirm = true; first = pin; }); }
                  else {
                    if (pin == first) {
                      await _storage.write(key: "app_pin", value: pin);
                      setModalState(() => _pinEnabled = true);
                      setState(() => _pinEnabled = true);
                      Navigator.pop(bCtx);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("PINs don't match")));
                    }
                  }
                },
                child: Text(confirm ? "Save PIN" : "Continue",
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showHelpSupport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Help & Support",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text("We are here 24/7 💙", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.phone, color: _teal),
            title: const Text("+1 234 567 890", style: TextStyle(color: Colors.white)),
            onTap: () async => await launchUrl(Uri(scheme: 'tel', path: '+1234567890')),
          ),
          ListTile(
            leading: const Icon(Icons.email, color: _blue),
            title: const Text("support@stresscare.com", style: TextStyle(color: Colors.white)),
            onTap: () async => await launchUrl(Uri(scheme: 'mailto', path: 'support@stresscare.com')),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ── Dark Input Field ──────────────────────────────────────────────────────
  Widget _darkField(TextEditingController ctrl, String label,
      {TextInputType type = TextInputType.text,
       bool readOnly = false,
       bool obscure = false,
       int? maxLen}) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        readOnly: readOnly,
        obscureText: obscure,
        maxLength: maxLen,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          counterStyle: const TextStyle(color: Colors.transparent, fontSize: 0),
        ),
      );
}

// ── Ring Painter ─────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  _RingPainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c  = Offset(size.width / 2, size.height / 2);
    final r  = (size.width - 8) / 2;
    final bg = Paint()
      ..color  = Colors.white.withOpacity(0.08)
      ..style  = PaintingStyle.stroke
      ..strokeWidth = 5;
    final fg = Paint()
      ..color  = color
      ..style  = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * fraction,
        false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
