package com.nguyenductien.backend.service;

import java.util.List;

import com.nguyenductien.backend.dto.auth.SessionResponse;
import com.nguyenductien.backend.entity.RefreshToken;
import com.nguyenductien.backend.entity.User;

public interface RefreshTokenService {

    RefreshToken createRefreshToken(User user, String deviceInfo, String ipAddress);

    RefreshToken verifyActiveToken(String token);

    void revokeToken(String token);

    void revokeSession(Long sessionId, User currentUser);

    void revokeAllSessions(User currentUser);

    List<SessionResponse> getActiveSessions(User currentUser);
}
