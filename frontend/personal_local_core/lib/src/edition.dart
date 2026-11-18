/// What this personal edition changes, and what it does not prove.
class PersonalEdition {
  const PersonalEdition._();

  static const bool accountFree = true;

  /// Hidden or removed from the user-facing local edition.
  /// The upstream implementation of these services can still exist in the tree.
  static const hiddenActions = <String>[
    'sign_in',
    'sign_up',
    'oauth',
    'magic_link',
    'cloud_sync',
    'cloud_share',
    'publish',
    'account_upgrade',
    'billing',
    'members',
    'ai_chat',
    'ai_writer',
    'newsletter_prompt',
  ];

  /// Local features this edition keeps.
  static const keptActions = <String>[
    'document',
    'grid',
    'board',
    'calendar',
    'local_search',
    'batch_edit',
    'memo_popout',
    'file_exchange',
  ];

  static bool isHidden(String action) => hiddenActions.contains(action);

  static bool isKept(String action) => keptActions.contains(action);

  /// Startup tasks this edition does not run.
  /// This is not a packet capture. Other code in the upstream tree can still
  /// open sockets if a caller reaches it.
  static const startupTasksNotRun = <String>[
    'InitAppFlowyCloudTask',
    'AutoUpdateTask',
    'AppFlowyCloudDeepLink',
    'default_cloud_url_write',
  ];

  /// Upstream pieces that remain in the repository. They are not deleted.
  static const remainingUpstreamNetworkComponents = <String>[
    'Rust HTTP clients in flowy-server / flowy-ai',
    'AppFlowyAIService registration',
    'cached_network_image for notes that already contain remote URLs',
    'connectivity_plus local network-status check (not a content upload)',
    'url_launcher for links a person chooses to open',
    'Sentry DSN field (empty unless a build injects one)',
    'ShareConstants and cloud URL helpers',
  ];
}
