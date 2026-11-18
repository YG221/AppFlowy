import 'package:appflowy/personal_local/personal_local_edition.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:personal_local_ui/personal_local_ui.dart';

/// Opens an existing local workspace, or shows a local create screen.
/// It does not show sign-in, sign-up, or cloud onboarding.
class PersonalLocalBootstrap extends StatefulWidget {
  const PersonalLocalBootstrap({super.key});

  @override
  State<PersonalLocalBootstrap> createState() => _PersonalLocalBootstrapState();
}

class _PersonalLocalBootstrapState extends State<PersonalLocalBootstrap> {
  var _needsCreate = false;
  var _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final current = await getIt<AuthService>().getUser();
    if (!mounted) {
      return;
    }
    final opened = await current.fold(
      (user) async {
        final decision = LocalStartupPlanner.decide(
          hasCurrentLocalUser: true,
          hasHistoricalLocalUser: false,
          storedCloudType: 0,
        );
        if (decision.contactsCloud || decision.showsAuthScreen) {
          return false;
        }
        await getIt<AuthRouter>().goHomeScreen(context, user);
        return true;
      },
      (_) async => false,
    );
    if (opened || !mounted) {
      return;
    }

    final historical = await UserBackendService.getAnonUser();
    if (!mounted) {
      return;
    }
    final hasHistorical = historical.fold((_) => true, (_) => false);
    final decision = LocalStartupPlanner.decide(
      hasCurrentLocalUser: false,
      hasHistoricalLocalUser: hasHistorical,
      storedCloudType: null,
    );
    if (decision.route == StartupRoute.openHistoricalLocalUser) {
      await UserBackendService.openAnonUser();
      if (!mounted) {
        return;
      }
      await runAppFlowy();
      return;
    }
    setState(() {
      _busy = false;
      _needsCreate = true;
    });
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await getIt<AuthService>().signUpAsGuest();
    if (!mounted) {
      return;
    }
    await result.fold(
      (user) => getIt<AuthRouter>().goHomeScreen(context, user),
      (error) async {
        Log.error(error);
        setState(() {
          _busy = false;
          _error = '로컬 작업공간을 만들지 못했습니다.';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_needsCreate) {
      return Column(
        children: [
          Expanded(child: LocalCreateGate(onCreate: _busy ? () {} : _create)),
          if (_error != null) Text(_error!),
        ],
      );
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
