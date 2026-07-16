import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';
import '../../../mobile_error_reporter.dart';
import '../../../user_data_deletion.dart';

class UserDataDeletionAccessItem extends StatelessWidget {
  const UserDataDeletionAccessItem({
    required this.repository,
    required this.deletionScope,
    required this.onDeleted,
    super.key,
  });

  final UserDataDeletionRepository repository;
  final UserDataDeletionScope deletionScope;
  final Future<void> Function(UserDataDeletionResult result)? onDeleted;

  @override
  Widget build(BuildContext context) {
    final copy = _UserDataDeletionCopy.forScope(deletionScope);
    void openDeletionScreen() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserDataDeletionScreen(
            repository: repository,
            deletionScope: deletionScope,
            onDeleted: onDeleted,
          ),
        ),
      );
    }

    return Semantics(
      key: const Key('dataDeletionAccessItem'),
      button: true,
      label: '${copy.title}, ${copy.helperText}',
      onTap: openDeletionScreen,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: openDeletionScreen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.delete_outline,
                    color: EasySubwayAccessibleColors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    copy.title,
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: EasySubwayAccessibleColors.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum UserDataDeletionScope {
  requestOnly,
  deviceOnly,
  remoteOnly,
  remoteAndDevice,
}

UserDataDeletionScope userDataDeletionScope(
  UserDataDeletionRepository? repository,
) {
  if (repository == null) {
    return UserDataDeletionScope.requestOnly;
  }
  if (repository is UserDataDeletionCompositeRepository) {
    return UserDataDeletionScope.remoteAndDevice;
  }
  if (repository is UserDataDeletionApiRepository) {
    return UserDataDeletionScope.remoteOnly;
  }
  return UserDataDeletionScope.deviceOnly;
}

class _UserDataDeletionCopy {
  const _UserDataDeletionCopy({
    required this.title,
    required this.helperText,
    required this.deletedSummary,
    required this.confirmText,
    this.exceptionNote,
  });

  factory _UserDataDeletionCopy.forScope(UserDataDeletionScope scope) {
    return switch (scope) {
      UserDataDeletionScope.requestOnly => const _UserDataDeletionCopy(
        title: '내 정보 삭제 요청',
        helperText: '메일로 삭제를 문의합니다.',
        deletedSummary: '삭제가 필요한 정보와 방법을 지원 메일로 문의합니다.',
        confirmText: '내 정보 삭제 요청 메일을 보낼까요?',
      ),
      UserDataDeletionScope.deviceOnly => const _UserDataDeletionCopy(
        title: '이 기기의 앱 정보 삭제',
        helperText: '이 기기에서 지울 정보를 확인합니다.',
        deletedSummary: '즐겨찾기, 최근 검색, 이동 조건, 화면 설정이 이 기기에서 지워져요.',
        exceptionNote: '이미 보낸 시설 제보와 사진은 그대로 남아요.',
        confirmText: '이 기기의 즐겨찾기·최근 검색·설정이 지워지고 되돌릴 수 없어요.',
      ),
      UserDataDeletionScope.remoteOnly => const _UserDataDeletionCopy(
        title: '보낸 정보 삭제',
        helperText: '보낸 정보 삭제 범위를 확인합니다.',
        deletedSummary: '보낸 제보와 사진·위치, 즐겨찾기, 이동 조건이 삭제되거나 익명 처리돼요.',
        confirmText: '보낸 정보와 설정이 삭제·익명 처리되고 되돌릴 수 없어요.',
      ),
      UserDataDeletionScope.remoteAndDevice => const _UserDataDeletionCopy(
        title: '내 정보 삭제',
        helperText: '삭제 범위를 확인합니다.',
        deletedSummary: '이 기기의 즐겨찾기·최근 검색·설정과 보낸 제보·사진이 삭제되거나 익명 처리돼요.',
        confirmText: '이 기기와 보낸 정보가 삭제·익명 처리되고 되돌릴 수 없어요.',
      ),
    };
  }

  final String title;
  final String helperText;
  final String deletedSummary;
  final String? exceptionNote;
  final String confirmText;

  static const irreversibleLine = '삭제 후에는 되돌릴 수 없어요.';
}

class UserDataDeletionScreen extends StatefulWidget {
  const UserDataDeletionScreen({
    required this.repository,
    required this.deletionScope,
    required this.onDeleted,
    super.key,
  });

  final UserDataDeletionRepository repository;
  final UserDataDeletionScope deletionScope;
  final Future<void> Function(UserDataDeletionResult result)? onDeleted;

  @override
  State<UserDataDeletionScreen> createState() => _UserDataDeletionScreenState();
}

class _UserDataDeletionScreenState extends State<UserDataDeletionScreen> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final copy = _UserDataDeletionCopy.forScope(widget.deletionScope);
    return Scaffold(
      appBar: AppBar(title: Text(copy.title)),
      bottomNavigationBar: Padding(
        padding: easySubwayBottomActionInsets(context),
        child: FilledButton.icon(
          key: const Key('dataDeletionStartButton'),
          onPressed: _isDeleting ? null : _confirmAndDelete,
          icon: _isDeleting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.delete_forever_outlined),
          label: Text(_isDeleting ? '삭제 중' : copy.title),
          style: FilledButton.styleFrom(
            backgroundColor: EasySubwayAccessibleColors.red,
            foregroundColor: EasySubwayAccessibleColors.surface,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: mainPagePadding,
          children: [
            Semantics(
              header: true,
              child: Text(
                '삭제 전에 확인해 주세요',
                style: textTheme.headlineSmall?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              copy.deletedSummary,
              style: textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _UserDataDeletionCopy.irreversibleLine,
              style: textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.red,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            if (copy.exceptionNote != null) ...[
              const SizedBox(height: 10),
              Text(
                copy.exceptionNote!,
                style: textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('정말 삭제할까요?'),
        content: Text(
          _UserDataDeletionCopy.forScope(widget.deletionScope).confirmText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('dataDeletionConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: EasySubwayAccessibleColors.red,
              foregroundColor: EasySubwayAccessibleColors.surface,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteCurrentUserData();
    }
  }

  Future<void> _deleteCurrentUserData() async {
    setState(() {
      _isDeleting = true;
    });
    try {
      final result = await widget.repository.deleteCurrentUserData();
      await widget.onDeleted?.call(result);
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on UserDataDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '사용자 정보 삭제 처리 중 예외가 발생했습니다.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(userDataDeletionErrorMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
}

class UserDataDeletionResultScreen extends StatelessWidget {
  const UserDataDeletionResultScreen({required this.onRestart, super.key});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('삭제 완료'),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: Padding(
        padding: easySubwayBottomActionInsets(context),
        child: FilledButton.icon(
          key: const Key('dataDeletionResultStartButton'),
          onPressed: onRestart,
          icon: const Icon(Icons.restart_alt),
          label: const Text('처음부터 시작'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: mainPagePadding,
          children: [
            AppCard(
              backgroundColor: EasySubwayAccessibleColors.surface,
              borderColor: EasySubwayAccessibleColors.line,
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: EasySubwayAccessibleColors.mintDark,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '내 정보가 삭제됐어요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '앱이 처음 사용하는 상태로 돌아갑니다.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const AppCard(
              showBorder: true,
              child: AppInfoRow(
                icon: Icons.map_outlined,
                iconColor: EasySubwayAccessibleColors.primary,
                title: '노선도와 역 정보는 계속 이용할 수 있어요',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
