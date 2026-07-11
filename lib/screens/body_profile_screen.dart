import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';

const _personalColors = ['봄웜', '여름쿨', '가을웜', '겨울쿨'];
const _bodyTypes = ['마른 체형', '보통 체형', '통통한 체형', '근육질 체형', '해당 없음/모름'];
const _styleOptions = ['캐주얼', '포멀', '스트릿', '미니멀', '스포티'];

class BodyProfileScreen extends StatefulWidget {
  const BodyProfileScreen({super.key});

  @override
  State<BodyProfileScreen> createState() => _BodyProfileScreenState();
}

class _BodyProfileScreenState extends State<BodyProfileScreen> {
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _waistController = TextEditingController();
  final _chestController = TextEditingController();

  String? _personalColor;
  String? _bodyType;
  final Set<String> _preferredStyles = {};

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _waistController.dispose();
    _chestController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final profile = await FirestoreService.getUserProfile(uid);
      if (profile != null) {
        _heightController.text = profile.heightCm?.toString() ?? '';
        _weightController.text = profile.weightKg?.toString() ?? '';
        _waistController.text = profile.waistCm?.toString() ?? '';
        _chestController.text = profile.chestCm?.toString() ?? '';
        _personalColor = profile.personalColor;
        _bodyType = profile.bodyType;
        _preferredStyles.addAll(profile.preferredStyles);
      }
    } catch (e) {
      // 로드 실패 시 빈 폼으로 시작 — 저장할 때 다시 시도하면 된다.
      debugPrint('[체형프로필조회] 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _isSaving) return;

    setState(() => _isSaving = true);
    final profile = UserProfile(
      heightCm: int.tryParse(_heightController.text.trim()),
      weightKg: double.tryParse(_weightController.text.trim()),
      personalColor: _personalColor,
      bodyType: _bodyType == '해당 없음/모름' ? null : _bodyType,
      waistCm: int.tryParse(_waistController.text.trim()),
      chestCm: int.tryParse(_chestController.text.trim()),
      preferredStyles: _preferredStyles.toList(),
    );

    try {
      await FirestoreService.saveUserProfile(uid, profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('체형 정보를 저장했습니다'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.greenDark,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('저장 실패: $e'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.red,
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.navy, strokeWidth: 2))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '전부 선택 입력입니다. 입력하지 않아도 앱 이용에 문제없습니다.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        _buildCard(
                          title: '기본 정보',
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildNumberField(
                                    controller: _heightController, label: '키(cm)'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildNumberField(
                                    controller: _weightController, label: '몸무게(kg)'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          title: '퍼스널 컬러',
                          child: _buildChoiceChips(
                            options: _personalColors,
                            selected: _personalColor,
                            onSelect: (v) => setState(
                                () => _personalColor = _personalColor == v ? null : v),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          title: '체형 타입',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildChoiceChips(
                                options: _bodyTypes,
                                selected: _bodyType,
                                onSelect: (v) => setState(
                                    () => _bodyType = _bodyType == v ? null : v),
                              ),
                              const SizedBox(height: 16),
                              const Text('상세 치수 (선택)',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildNumberField(
                                        controller: _waistController, label: '허리둘레(cm)'),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildNumberField(
                                        controller: _chestController, label: '가슴둘레(cm)'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCard(
                          title: '선호 스타일 (다중 선택)',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _styleOptions.map((style) {
                              final isSelected = _preferredStyles.contains(style);
                              return FilterChip(
                                label: Text(style),
                                selected: isSelected,
                                onSelected: (_) => setState(() {
                                  if (isSelected) {
                                    _preferredStyles.remove(style);
                                  } else {
                                    _preferredStyles.add(style);
                                  }
                                }),
                                selectedColor: AppColors.bluePale,
                                checkmarkColor: AppColors.blue,
                                labelStyle: TextStyle(
                                    color: isSelected ? AppColors.blue : AppColors.textSecondary,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                                backgroundColor: AppColors.background,
                                side: BorderSide(
                                    color: isSelected ? AppColors.blue : AppColors.border),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSaveButton(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: AppColors.background, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          const Text('체형 정보',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildNumberField({required TextEditingController controller, required String label}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  Widget _buildChoiceChips({
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (_) => onSelect(option),
          selectedColor: AppColors.bluePale,
          labelStyle: TextStyle(
              color: isSelected ? AppColors.blue : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
          backgroundColor: AppColors.background,
          side: BorderSide(color: isSelected ? AppColors.blue : AppColors.border),
        );
      }).toList(),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _save,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _isSaving ? AppColors.textDisabled : AppColors.navy,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('저장',
                  style: TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
