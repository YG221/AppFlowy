export 'package:personal_local_core/personal_local_core.dart'
    show
        PersonalEdition,
        StorageEncryptionBlocker,
        LocalStartupPlanner,
        StartupDecision,
        StartupRoute;

/// This fork is a local note edition. The flag is compile-time on purpose.
class PersonalLocalEdition {
  const PersonalLocalEdition._();

  static const bool enabled = true;

  static const disabledFeatureFlags = <String>[
    'planBilling',
    'collaborativeWorkspace',
    'membersSettings',
    'syncDatabase',
    'syncDocument',
    'sharedSection',
  ];
}
