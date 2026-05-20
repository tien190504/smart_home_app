class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.enabled,
    required this.roles,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .map((role) => role.toString())
          .toSet(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  final int id;
  final String fullName;
  final String email;
  final bool enabled;
  final Set<String> roles;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'enabled': enabled,
      'roles': roles.toList(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      accessTokenExpiresAt: DateTime.parse(
        json['accessTokenExpiresAt'] as String,
      ),
      refreshToken: json['refreshToken'] as String? ?? '',
      refreshTokenExpiresAt: DateTime.parse(
        json['refreshTokenExpiresAt'] as String,
      ),
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final UserProfile user;

  bool get isAccessExpired =>
      accessTokenExpiresAt.isBefore(DateTime.now().add(const Duration(seconds: 20)));

  bool get isRefreshExpired => refreshTokenExpiresAt.isBefore(DateTime.now());

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
      'refreshToken': refreshToken,
      'refreshTokenExpiresAt': refreshTokenExpiresAt.toIso8601String(),
      'user': user.toJson(),
    };
  }
}

class AuthResponseModel {
  const AuthResponseModel({
    required this.accessToken,
    required this.accessTokenExpiresInMs,
    required this.refreshToken,
    required this.refreshTokenExpiresInMs,
    required this.user,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      accessToken: json['accessToken'] as String? ?? '',
      accessTokenExpiresInMs: (json['accessTokenExpiresInMs'] as num?)?.toInt() ?? 0,
      refreshToken: json['refreshToken'] as String? ?? '',
      refreshTokenExpiresInMs:
          (json['refreshTokenExpiresInMs'] as num?)?.toInt() ?? 0,
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String accessToken;
  final int accessTokenExpiresInMs;
  final String refreshToken;
  final int refreshTokenExpiresInMs;
  final UserProfile user;

  AuthSession toSession() {
    final now = DateTime.now();
    return AuthSession(
      accessToken: accessToken,
      accessTokenExpiresAt: now.add(
        Duration(milliseconds: accessTokenExpiresInMs),
      ),
      refreshToken: refreshToken,
      refreshTokenExpiresAt: now.add(
        Duration(milliseconds: refreshTokenExpiresInMs),
      ),
      user: user,
    );
  }
}

enum AuthStatus {
  unknown,
  submitting,
  authenticated,
  unauthenticated,
}

class AuthState {
  const AuthState({
    required this.status,
    required this.rememberMe,
    this.session,
    this.errorMessage,
  });

  const AuthState.unknown()
      : this(status: AuthStatus.unknown, rememberMe: true);

  const AuthState.unauthenticated({
    bool rememberMe = true,
    String? errorMessage,
  }) : this(
          status: AuthStatus.unauthenticated,
          rememberMe: rememberMe,
          errorMessage: errorMessage,
        );

  const AuthState.authenticated(
    AuthSession session, {
    bool rememberMe = true,
  }) : this(
          status: AuthStatus.authenticated,
          rememberMe: rememberMe,
          session: session,
        );

  final AuthStatus status;
  final bool rememberMe;
  final AuthSession? session;
  final String? errorMessage;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && session != null;

  bool get isBusy => status == AuthStatus.submitting;

  AuthState copyWith({
    AuthStatus? status,
    bool? rememberMe,
    AuthSession? session,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      rememberMe: rememberMe ?? this.rememberMe,
      session: session ?? this.session,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
