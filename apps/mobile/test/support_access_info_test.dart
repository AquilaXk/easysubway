import 'package:easysubway_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('릴리즈 도움말 연락 경로는 모두 설정되어야 한다', () {
    expect(
      () => const SupportAccessInfo(
        privacyPolicyUrl: '',
        supportEmail: 'support@easysubway.example',
        dataDeletionEmail: 'privacy@easysubway.example',
        securityEmail: 'security@easysubway.example',
      ).validatedForBuild(isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release privacy policy URL must be configured.',
        ),
      ),
    );
    expect(
      () => const SupportAccessInfo(
        privacyPolicyUrl: 'https://easysubway.example/privacy',
        supportEmail: '',
        dataDeletionEmail: 'privacy@easysubway.example',
        securityEmail: 'security@easysubway.example',
      ).validatedForBuild(isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release support email must be configured.',
        ),
      ),
    );
    expect(
      () => const SupportAccessInfo(
        privacyPolicyUrl: 'https://easysubway.example/privacy',
        supportEmail: 'support@easysubway.example',
        dataDeletionEmail: '',
        securityEmail: 'security@easysubway.example',
      ).validatedForBuild(isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release data deletion email must be configured.',
        ),
      ),
    );
    expect(
      () => const SupportAccessInfo(
        privacyPolicyUrl: 'https://easysubway.example/privacy',
        supportEmail: 'support@easysubway.example',
        dataDeletionEmail: 'privacy@easysubway.example',
        securityEmail: '',
      ).validatedForBuild(isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release security email must be configured.',
        ),
      ),
    );
  });

  test('릴리즈 도움말 연락 경로는 HTTPS와 메일 주소 형식만 허용한다', () {
    expect(
      () => const SupportAccessInfo(
        privacyPolicyUrl: 'http://easysubway.example/privacy',
        supportEmail: 'support@easysubway.example',
        dataDeletionEmail: 'privacy@easysubway.example',
        securityEmail: 'security@easysubway.example',
      ).validatedForBuild(isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release privacy policy URL must use HTTPS.',
        ),
      ),
    );
    expect(
      () => const SupportAccessInfo(
        privacyPolicyUrl: 'https://easysubway.example/privacy',
        supportEmail: 'support',
        dataDeletionEmail: 'privacy@easysubway.example',
        securityEmail: 'security@easysubway.example',
      ).validatedForBuild(isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release support email must be a valid email address.',
        ),
      ),
    );
    expect(
      const SupportAccessInfo(
        privacyPolicyUrl: 'https://easysubway.example/privacy',
        supportEmail: 'support@easysubway.example',
        dataDeletionEmail: 'privacy@easysubway.example',
        securityEmail: 'security@easysubway.example',
      ).validatedForBuild(isReleaseMode: true).securityEmail,
      'security@easysubway.example',
    );
  });

  test('디버그 도움말 연락 경로는 준비 중 표시를 위해 비어 있을 수 있다', () {
    expect(
      const SupportAccessInfo(
        privacyPolicyUrl: '',
        supportEmail: '',
        dataDeletionEmail: '',
      ).validatedForBuild(isReleaseMode: false).privacyPolicyUrl,
      isEmpty,
    );
  });
}
