enum StartupRoute {
  openCurrentLocalUser,
  openHistoricalLocalUser,
  showLocalCreate,
}

class StartupDecision {
  const StartupDecision({
    required this.route,
    required this.showsAuthScreen,
    required this.contactsCloud,
    required this.rewritesStoredCloudType,
    required this.importsRemoteData,
    required this.messageKo,
  });

  final StartupRoute route;
  final bool showsAuthScreen;
  final bool contactsCloud;
  final bool rewritesStoredCloudType;
  final bool importsRemoteData;
  final String messageKo;
}

class LocalStartupPlanner {
  const LocalStartupPlanner._();

  /// [storedCloudType] is the existing KV value. `0` is local. `null` means
  /// unset. Any other value is left untouched and is not used to download data.
  static StartupDecision decide({
    required bool hasCurrentLocalUser,
    required bool hasHistoricalLocalUser,
    required int? storedCloudType,
  }) {
    final remoteLeftAlone = storedCloudType != null && storedCloudType != 0;
    final message = StringBuffer('계정 없이 이 폴더의 로컬 작업공간을 엽니다.');
    if (remoteLeftAlone) {
      message.write(
        ' 저장된 클라우드 설정은 바꾸지 않고, 원격 계정 데이터는 가져오거나 지우지 않습니다.',
      );
    }

    final StartupRoute route;
    if (hasCurrentLocalUser) {
      route = StartupRoute.openCurrentLocalUser;
    } else if (hasHistoricalLocalUser) {
      route = StartupRoute.openHistoricalLocalUser;
    } else {
      route = StartupRoute.showLocalCreate;
    }

    return StartupDecision(
      route: route,
      showsAuthScreen: false,
      contactsCloud: false,
      rewritesStoredCloudType: false,
      importsRemoteData: false,
      messageKo: message.toString(),
    );
  }
}
