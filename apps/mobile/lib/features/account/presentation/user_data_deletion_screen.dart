import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import '../../../user_data_deletion.dart';

class UserDataDeletionAccessItem extends StatelessWidget {
  const UserDataDeletionAccessItem({
    required this.repository,
    required this.onDeleted,
    super.key,
  });

  final UserDataDeletionRepository repository;
  final Future<void> Function(UserDataDeletionResult result)? onDeleted;

  @override
  Widget build(BuildContext context) {
    final deletionScope = _userDataDeletionScope(repository);
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
      container: true,
      label: '${copy.title}, ${copy.helperText}',
      onTap: openDeletionScreen,
      child: ExcludeSemantics(
        child: ListTile(
          onTap: openDeletionScreen,
          minVerticalPadding: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          tileColor: EasySubwayAccessibleColors.surface,
          title: Text(
            copy.title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          subtitle: Text(
            copy.helperText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.mutedText,
              height: 1.3,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: EasySubwayAccessibleColors.disclosure,
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

UserDataDeletionScope _userDataDeletionScope(
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
    final copy = _UserDataDeletionCopy.forScope(widget.deletionScope);
    final noticeLines = <Widget>[
      _UserDataNoticeBullet(text: copy.deletedSummary),
      const SizedBox(height: 10),
      const _UserDataNoticeBullet(
        text: _UserDataDeletionCopy.irreversibleLine,
        emphasis: true,
      ),
      if (copy.exceptionNote != null) ...[
        const SizedBox(height: 10),
        _UserDataNoticeBullet(text: copy.exceptionNote!, muted: true),
      ],
    ];
    return Scaffold(
      key: const Key('userDataDeletionScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('userDataDeletionAppBar'),
        title: Text(copy.title),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('userDataDeletionBackButton'),
          tooltip: '뒤로',
          onPressed: _isDeleting
              ? null
              : () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(EasySubwayTouchTarget.general),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(
            Icons.arrow_back,
            size: 26,
            color: Color(0xFF4B4B4B),
          ),
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(
            key: Key('userDataDeletionHeaderDivider'),
          ),
        ),
      ),
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
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ColoredBox(
              key: const Key('userDataDeletionSectionHeader'),
              color: EasySubwayAccessibleColors.scaffoldSurface,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: Semantics(
                    header: true,
                    child: Text(
                      '삭제 전에 확인해 주세요',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: EasySubwayAccessibleColors.secondaryText,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ColoredBox(
              color: EasySubwayAccessibleColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: noticeLines,
                ),
              ),
            ),
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
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      key: const Key('userDataDeletionResultScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('userDataDeletionResultAppBar'),
        title: const Text('삭제 완료'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(
            key: Key('userDataDeletionResultHeaderDivider'),
          ),
        ),
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
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ColoredBox(
              color: EasySubwayAccessibleColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
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
                      style: textTheme.titleLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '앱이 처음 사용하는 상태로 돌아갑니다.',
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.mutedText,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            ColoredBox(
              color: EasySubwayAccessibleColors.scaffoldSurface,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: Semantics(
                    header: true,
                    child: Text(
                      '이용 안내',
                      style: textTheme.bodyMedium?.copyWith(
                        color: EasySubwayAccessibleColors.secondaryText,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ColoredBox(
              color: EasySubwayAccessibleColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      color: EasySubwayAccessibleColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '노선도와 역 정보는 계속 이용할 수 있어요',
                        style: textTheme.bodyLarge?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserDataNoticeBullet extends StatelessWidget {
  const _UserDataNoticeBullet({
    required this.text,
    this.emphasis = false,
    this.muted = false,
  });

  final String text;
  final bool emphasis;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = emphasis
        ? EasySubwayAccessibleColors.red
        : muted
        ? EasySubwayAccessibleColors.mutedText
        : EasySubwayAccessibleColors.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: emphasis
                  ? EasySubwayAccessibleColors.red
                  : EasySubwayAccessibleColors.secondaryText,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: color,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
