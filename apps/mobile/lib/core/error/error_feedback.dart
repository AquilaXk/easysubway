import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// 에러 문구를 스크린리더에 즉시 공지한다.
Future<void> announceErrorMessage(
  String message, {
  BuildContext? context,
}) async {
  final FlutterView? view = context != null
      ? View.maybeOf(context)
      : WidgetsBinding.instance.platformDispatcher.implicitView ??
            (WidgetsBinding.instance.platformDispatcher.views.isEmpty
                ? null
                : WidgetsBinding.instance.platformDispatcher.views.first);
  if (view == null || message.trim().isEmpty) {
    return;
  }
  await SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
}

void showAnnouncedErrorSnackBar(
  BuildContext context,
  String message, {
  String? correlationId,
  SnackBarAction? action,
}) {
  announceErrorMessage(message, context: context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action:
            action ??
            (correlationId == null
                ? null
                : SnackBarAction(
                    label: '참조 번호',
                    onPressed: () {
                      showErrorReferenceSheet(
                        context,
                        message: message,
                        correlationId: correlationId,
                      );
                    },
                  )),
      ),
    );
}

/// 사용자에게 코드 원문 없이 correlationId만 "문의 시 참조 번호"로 보여 준다.
Future<void> showErrorReferenceSheet(
  BuildContext context, {
  required String message,
  required String correlationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                key: const Key('errorReferenceExpansion'),
                initiallyExpanded: true,
                title: const Text('문의 시 참조 번호'),
                children: [
                  ListTile(
                    key: const Key('errorReferenceId'),
                    title: SelectableText(correlationId),
                    trailing: IconButton(
                      key: const Key('errorReferenceCopy'),
                      tooltip: '참조 번호 복사',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: correlationId),
                        );
                        if (!sheetContext.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('참조 번호를 복사했어요.')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 인라인 에러 영역에 참조 번호 접기 UI를 붙일 때 사용한다.
class ErrorReferenceDetails extends StatelessWidget {
  const ErrorReferenceDetails({
    super.key,
    required this.message,
    this.correlationId,
  });

  final String message;
  final String? correlationId;

  @override
  Widget build(BuildContext context) {
    final hasMessage = message.trim().isNotEmpty;
    final hasCorrelation =
        correlationId != null && correlationId!.trim().isNotEmpty;
    if (!hasMessage && !hasCorrelation) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasMessage) Text(message),
        if (hasCorrelation) ...[
          if (hasMessage) const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('errorReferenceExpansion'),
            initiallyExpanded: true,
            tilePadding: EdgeInsets.zero,
            title: const Text('문의 시 참조 번호'),
            children: [
              SelectableText(
                correlationId!,
                key: const Key('errorReferenceId'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
