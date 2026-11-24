import 'package:personal_local_core/personal_local_core.dart';
import 'package:test/test.dart';

void main() {
  test('account-free startup never shows auth or contacts cloud', () {
    final existing = LocalStartupPlanner.decide(
      hasCurrentLocalUser: true,
      hasHistoricalLocalUser: true,
      storedCloudType: 0,
    );
    expect(existing.route, StartupRoute.openCurrentLocalUser);
    expect(existing.showsAuthScreen, isFalse);
    expect(existing.contactsCloud, isFalse);
    expect(existing.importsRemoteData, isFalse);

    final first = LocalStartupPlanner.decide(
      hasCurrentLocalUser: false,
      hasHistoricalLocalUser: false,
      storedCloudType: null,
    );
    expect(first.route, StartupRoute.showLocalCreate);
    expect(first.showsAuthScreen, isFalse);

    final cloudLeftAlone = LocalStartupPlanner.decide(
      hasCurrentLocalUser: false,
      hasHistoricalLocalUser: true,
      storedCloudType: 2,
    );
    expect(cloudLeftAlone.route, StartupRoute.openHistoricalLocalUser);
    expect(cloudLeftAlone.rewritesStoredCloudType, isFalse);
    expect(cloudLeftAlone.importsRemoteData, isFalse);
    expect(cloudLeftAlone.messageKo, contains('원격 계정 데이터'));
  });

  test('auth actions are hidden and local views stay available', () {
    expect(PersonalEdition.isHidden('sign_in'), isTrue);
    expect(PersonalEdition.isHidden('ai_chat'), isTrue);
    expect(PersonalEdition.isHidden('publish'), isTrue);
    expect(PersonalEdition.isHidden('account_upgrade'), isTrue);
    expect(PersonalEdition.isKept('grid'), isTrue);
    expect(PersonalEdition.isKept('board'), isTrue);
    expect(PersonalEdition.isKept('calendar'), isTrue);
    expect(PersonalEdition.isKept('local_search'), isTrue);
    expect(PersonalEdition.startupTasksNotRun, contains('AutoUpdateTask'));
    expect(
      PersonalEdition.remainingUpstreamNetworkComponents,
      isNotEmpty,
    );
  });
}
