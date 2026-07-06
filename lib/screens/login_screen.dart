import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 54,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gray900,
                      letterSpacing: -1.5,
                      height: 1,
                    ),
                    children: [
                      TextSpan(text: 'DOT'),
                      TextSpan(text: '.', style: TextStyle(color: AppColors.accent)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '당신의 취향을 아는\n가장 쉬운 스타일링',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.gray500, height: 1.6),
                ),
              ],
            ),
          ),
          _SocialButton(
            label: 'Google로 계속하기',
            bg: Colors.white,
            fg: AppColors.gray900,
            border: AppColors.gray300,
            leading: const Text('G',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.google)),
            onTap: app.login,
          ),
          const SizedBox(height: 12),
          _SocialButton(
            label: '카카오로 계속하기',
            bg: AppColors.kakao,
            fg: AppColors.kakaoText,
            leading: const Icon(Icons.chat_bubble, size: 18, color: AppColors.kakaoText),
            onTap: app.login,
          ),
          const SizedBox(height: 12),
          _SocialButton(
            label: '네이버로 계속하기',
            bg: AppColors.naver,
            fg: Colors.white,
            leading: const Text('N',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
            onTap: app.login,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 18, 0, 26),
            child: Text(
              '계속 진행하면 이용약관 및 개인정보처리방침에\n동의하는 것으로 간주됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFFB5B5B5), height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;
  final Widget leading;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.bg,
    required this.fg,
    this.border,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: border != null ? Border.all(color: border!) : null,
        ),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: leading)),
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
            ),
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }
}