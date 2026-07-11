import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';
import 'body_profile_screen.dart';
import 'scrap_screen.dart';

const _settingsGroups = [
  {
    'title': '계정',
    'items': [
      {'icon': Icons.person, 'label': '프로필 설정', 'sub': '김민준 · 25세'},
      {'icon': Icons.notifications, 'label': '알림 설정', 'sub': 'AI 추천 알림 켜짐'},
    ],
  },
  {
    'title': '앱 설정',
    'items': [
      {'icon': Icons.bookmark, 'label': '내 스크랩', 'sub': null},
      {'icon': Icons.smartphone, 'label': '체형 정보', 'sub': null}, // 실시간 프로필 데이터로 대체됨
    ],
  },
  {
    'title': '기타',
    'items': [
      {'icon': Icons.shield, 'label': '개인정보 처리방침', 'sub': null},
      {'icon': Icons.help_outline, 'label': '고객센터', 'sub': '평일 09:00 - 18:00'},
    ],
  },
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile = await FirestoreService.getUserProfileSilently(uid);
    if (mounted) setState(() => _profile = profile);
  }

  String _bodyInfoSummary() {
    final profile = _profile;
    if (profile == null || !profile.hasAnyData) return '입력해 주세요';
    final parts = <String>[];
    if (profile.heightCm != null) parts.add('${profile.heightCm}cm');
    if (profile.weightKg != null) parts.add('${profile.weightKg}kg');
    if (profile.personalColor != null) parts.add(profile.personalColor!);
    return parts.isEmpty ? '입력됨' : parts.join(' · ');
  }

  void _openBodyProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BodyProfileScreen()),
    );
    _loadProfile();
  }

  void _openScraps() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScrapScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildProfileHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              children: [
                ..._settingsGroups.map((group) => _buildGroup(group)),
                const SizedBox(height: 8),
                const Text(
                  'StyleAI v1.0.0',
                  style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyLight],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person_outline, color: Colors.white70, size: 28),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('김민준', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
              SizedBox(height: 2),
              Text('내 옷장 8벌 · 착장 기록 5개', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(Map<String, dynamic> group) {
    final items = group['items'] as List;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              (group['title'] as String).toUpperCase(),
              style: const TextStyle(
                color: AppColors.textPlaceholder,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: List.generate(items.length, (i) {
                final item = items[i] as Map<String, dynamic>;
                final icon = item['icon'] as IconData;
                final label = item['label'] as String;
                final isBodyInfo = label == '체형 정보';
                final isMyScraps = label == '내 스크랩';
                final sub = isBodyInfo ? _bodyInfoSummary() : item['sub'] as String?;
                return Column(
                  children: [
                    InkWell(
                      onTap: isBodyInfo
                          ? _openBodyProfile
                          : (isMyScraps ? _openScraps : () {}),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: AppColors.bluePale, borderRadius: BorderRadius.circular(10)),
                              child: Icon(icon, color: AppColors.blue, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                                  if (sub != null) ...[
                                    const SizedBox(height: 1),
                                    Text(sub, style: const TextStyle(color: AppColors.textPlaceholder, fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 16),
                          ],
                        ),
                      ),
                    ),
                    if (i < items.length - 1)
                      const Divider(height: 1, color: AppColors.divider, indent: 64),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
