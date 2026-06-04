import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInAnonymously() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
      // 성공 시 StreamBuilder가 AppShell로 자동 전환
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('로그인 실패: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // 로고 영역
              _buildLogo(),
              const Spacer(flex: 2),
              // 로그인 버튼 영역
              _buildLoginButtons(),
              const SizedBox(height: 32),
              // 하단 안내
              _buildFooter(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.checkroom, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 20),
        const Text(
          'StyleAI',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'AI가 제안하는 나만의 코디',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButtons() {
    return Column(
      children: [
        // 비회원 로그인 (메인 버튼)
        GestureDetector(
          onTap: _isLoading ? null : _signInAnonymously,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: _isLoading ? AppColors.textDisabled : AppColors.navy,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _isLoading
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                else
                  const Icon(Icons.person_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  _isLoading ? '로그인 중...' : '비회원으로 시작하기',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 구분선
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '또는 SNS로 로그인',
                style: TextStyle(
                  color: AppColors.textPlaceholder,
                  fontSize: 12,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 20),
        // SNS 로그인 버튼들 (준비 중)
        Row(
          children: [
            Expanded(
              child: _SnsButton(
                label: 'Google',
                color: Colors.white,
                textColor: AppColors.textSecondary,
                borderColor: AppColors.border,
                icon: Icons.language,
                iconColor: const Color(0xFF4285F4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SnsButton(
                label: '네이버',
                color: const Color(0xFF03C75A),
                textColor: Colors.white,
                icon: Icons.search,
                iconColor: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SnsButton(
                label: '카카오',
                color: const Color(0xFFFEE500),
                textColor: const Color(0xFF3C1E1E),
                icon: Icons.chat_bubble_outline,
                iconColor: const Color(0xFF3C1E1E),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'SNS 로그인은 준비 중입니다',
          style: TextStyle(
            color: AppColors.textPlaceholder,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '비회원으로 시작하면 기기 변경 시 데이터가 유지되지 않을 수 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textDisabled,
            fontSize: 11,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ── SNS 버튼 (준비 중 뱃지 포함) ───────────────────────
class _SnsButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final Color? borderColor;
  final IconData icon;
  final Color iconColor;

  const _SnsButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.icon,
    required this.iconColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: borderColor != null ? Border.all(color: borderColor!) : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
