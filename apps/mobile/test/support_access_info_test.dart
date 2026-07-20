import 'package:easysubway_mobile/features/support/presentation/support_access_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SupportAccessInfo info({
    String terms = 'https://easysubway.example/terms',
    String privacy = 'https://easysubway.example/privacy',
    String location = 'https://easysubway.example/location-terms',
    String support = 'support@easysubway.example',
    String deletion = 'privacy@easysubway.example',
    String security = 'security@easysubway.example',
  }) => SupportAccessInfo(
    termsOfServiceUrl: terms,
    privacyPolicyUrl: privacy,
    locationTermsUrl: location,
    supportEmail: support,
    dataDeletionEmail: deletion,
    securityEmail: security,
  );

  test('릴리즈 법적 문서 URL은 모두 설정되어야 한다', () {
    for (final invalid in [
      (info(terms: ''), 'Release terms of service URL must be configured.'),
      (info(privacy: ''), 'Release privacy policy URL must be configured.'),
      (info(location: ''), 'Release location terms URL must be configured.'),
    ]) {
      expect(
        () => invalid.$1.validatedForBuild(isReleaseMode: true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            invalid.$2,
          ),
        ),
      );
    }
  });

  test('릴리즈 법적 문서는 HTTPS URL만 허용한다', () {
    for (final invalid in [
      (
        info(terms: 'http://easysubway.example/terms'),
        'Release terms of service URL must use HTTPS.',
      ),
      (
        info(privacy: 'http://easysubway.example/privacy'),
        'Release privacy policy URL must use HTTPS.',
      ),
      (
        info(location: 'location-terms'),
        'Release location terms URL must use HTTPS.',
      ),
    ]) {
      expect(
        () => invalid.$1.validatedForBuild(isReleaseMode: true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            invalid.$2,
          ),
        ),
      );
    }
  });

  test('릴리즈 법적 문서 URL은 호스트를 포함해야 한다', () {
    expect(
      () => info(
        location: 'https:/location-terms',
      ).validatedForBuild(isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release location terms URL must include a host.',
        ),
      ),
    );
  });

  test('릴리즈 문의 주소는 모두 유효해야 한다', () {
    for (final invalid in [
      (
        info(support: 'support'),
        'Release support email must be a valid email address.',
      ),
      (info(deletion: ''), 'Release data deletion email must be configured.'),
      (info(security: ''), 'Release security email must be configured.'),
    ]) {
      expect(
        () => invalid.$1.validatedForBuild(isReleaseMode: true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            invalid.$2,
          ),
        ),
      );
    }
    expect(
      info().validatedForBuild(isReleaseMode: true).securityEmail,
      'security@easysubway.example',
    );
  });

  test('디버그에서는 미설정 값을 허용한다', () {
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
