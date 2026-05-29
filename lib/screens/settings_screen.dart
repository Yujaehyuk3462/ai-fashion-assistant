import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

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
      {'icon': Icons.dark_mode, 'label': '다크 모드', 'sub': '시스템 설정 따름'},
      {'icon': Icons.smartphone, 'label': '체형 정보', 'sub': '170cm · 65kg · M사이즈'},
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
                  'StyleAI v1.0.0 · Made with ❤️',
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
            child: const Center(child: Text('😎', style: TextStyle(fontSize: 24))),
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
                final sub = item['sub'] as String?;
                return Column(
                  children: [
                    InkWell(
                      onTap: () {},
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