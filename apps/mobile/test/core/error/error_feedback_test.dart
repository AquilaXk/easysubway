import 'package:easysubway_mobile/core/error/error_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ErrorReferenceDetails shows copyable correlation id', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorReferenceDetails(
            message: '잠시 후 다시 시도',
            correlationId: 'corr-ui-1',
          ),
        ),
      ),
    );

    expect(find.text('잠시 후 다시 시도'), findsOneWidget);
    expect(find.text('문의 시 참조 번호'), findsOneWidget);
    expect(find.byKey(const Key('errorReferenceId')), findsOneWidget);
    expect(find.text('corr-ui-1'), findsOneWidget);
  });

  testWidgets('showAnnouncedErrorSnackBar shows snackbar message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showAnnouncedErrorSnackBar(context, '공지 테스트 오류');
                },
                child: const Text('trigger'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pump();
    expect(find.text('공지 테스트 오류'), findsOneWidget);
  });
}
