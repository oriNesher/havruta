import 'package:flutter_test/flutter_test.dart';
import 'package:havruta/services/deep_link_service.dart';

void main() {
  String? extract(String url) =>
      DeepLinkService.extractInviteLinkId(Uri.parse(url));

  group('invite links that should be recognised', () {
    test('the shared /i/ link, as App Links delivers it', () {
      expect(extract('https://havruta-app.web.app/i/abc123'), 'abc123');
    });

    test('the web /join/ link', () {
      expect(extract('https://havruta-app.web.app/join/abc123'), 'abc123');
    });

    test('a token carried in the fragment', () {
      expect(extract('https://havruta-app.web.app/#/join/abc123'), 'abc123');
      expect(extract('https://havruta-app.web.app/#/i/abc123'), 'abc123');
    });

    test('a trailing slash', () {
      expect(extract('https://havruta-app.web.app/join/abc123/'), 'abc123');
    });

    test('a query string riding along', () {
      expect(extract('https://havruta-app.web.app/join/abc123?src=sms'),
          'abc123');
    });

    test('localhost, which is where the web app is developed', () {
      expect(extract('http://localhost:5556/#/join/abc123'), 'abc123');
    });
  });

  group('URLs that are not invites', () {
    test('the bare app root', () {
      expect(extract('https://havruta-app.web.app/'), isNull);
      expect(extract('https://havruta-app.web.app'), isNull);
    });

    test('a prefix with no token after it', () {
      expect(extract('https://havruta-app.web.app/i/'), isNull);
      expect(extract('https://havruta-app.web.app/join'), isNull);
    });

    test('an unrelated path that merely contains the prefix', () {
      expect(extract('https://havruta-app.web.app/privacy/i/abc'), isNull);
      expect(extract('https://havruta-app.web.app/invite/abc123'), isNull);
    });

    test('the app root after the token has been stripped from the URL', () {
      expect(extract('https://havruta-app.web.app/#/'), isNull);
    });
  });

  group('organizer dashboard links', () {
    String? organize(String url) =>
        DeepLinkService.extractOrganizerDashboardId(Uri.parse(url));

    test('/organize/{id} opens that dashboard', () {
      expect(organize('https://havruta-app.web.app/organize/c1'), 'c1');
      expect(organize('https://havruta-app.web.app/organize/c1/'), 'c1');
    });

    test('anything else does not', () {
      expect(organize('https://havruta-app.web.app/'), isNull);
      expect(organize('https://havruta-app.web.app/organize'), isNull);
      expect(organize('https://havruta-app.web.app/join/c1'), isNull);
    });

    test("a dashboard link isn't mistaken for an invite", () {
      expect(extract('https://havruta-app.web.app/organize/c1'), isNull);
    });
  });
}
