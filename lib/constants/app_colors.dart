import 'package:flutter/material.dart';

class AppColors {
  // 앱 메인(브랜드) 컬러 — 기존 네이비 대신 블랙 계열로 통일.
  // 다른 화면들이 참조하는 이름(navy/navyLight)은 그대로 유지한다.
  static const navy = Color(0xFF000000);
  static const navyLight = Color(0xFF2C2C2E);
  static const blue = Color(0xFF2563EB);
  static const blueLight = Color(0xFF3B82F6);
  static const bluePale = Color(0xFFEEF4FF);
  static const blueVeryPale = Color(0xFFF8FAFF);
  static const background = Color(0xFFF2F2F0);
  static const surface = Colors.white;
  static const border = Color(0xFFE8EAED);
  static const divider = Color(0xFFF2F2F0);
  static const textPrimary = Color(0xFF0D1B3E);
  static const textSecondary = Color(0xFF374151);
  static const textMuted = Color(0xFF6B7280);
  static const textPlaceholder = Color(0xFF9CA3AF);
  static const textDisabled = Color(0xFFCBD5E1);
  static const green = Color(0xFF22C55E);
  static const greenDark = Color(0xFF16A34A);
  static const greenPale = Color(0xFFDCFCE7);
  static const red = Color(0xFFEF4444);
  static const redPale = Color(0xFFFEE2E2);
  static const amber = Color(0xFFF59E0B);
  static const amberPale = Color(0xFFFFFBEB);
  static const teal = Color(0xFF10B981);
  static const tealPale = Color(0xFFECFDF5);
  static const purple = Color(0xFF7C3AED);

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    transform: GradientRotation(160 * 3.14159 / 180),
    colors: [navy, navyLight],
  );

  static const blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1D4ED8), blue, blueLight],
  );

  static const navyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, navyLight],
  );
}