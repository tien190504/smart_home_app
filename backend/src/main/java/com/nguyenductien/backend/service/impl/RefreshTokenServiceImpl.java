package com.nguyenductien.backend.service.impl;

import java.time.Instant;
import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.nguyenductien.backend.dto.auth.SessionResponse;
import com.nguyenductien.backend.entity.RefreshToken;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.exception.ResourceNotFoundException;
import com.nguyenductien.backend.exception.UnauthorizedException;
import com.nguyenductien.backend.mapper.SessionMapper;
import com.nguyenductien.backend.repository.RefreshTokenRepository;
import com.nguyenductien.backend.security.JwtService;
import com.nguyenductien.backend.service.RefreshTokenService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class RefreshTokenServiceImpl implements RefreshTokenService {

    private final RefreshTokenRepository refreshTokenRepository;
    private final JwtService jwtService;

    @Override
    @Transactional
    public RefreshToken createRefreshToken(User user, String deviceInfo, String ipAddress) {
        RefreshToken refreshToken = RefreshToken.builder()
                .token(jwtService.generateRefreshToken(user))
                .expiresAt(Instant.now().plusMillis(jwtService.getRefreshTokenExpiration()))
                .deviceInfo(deviceInfo)
                .ipAddress(ipAddress)
                .user(user)
                .revoked(false)
                .build();

        return refreshTokenRepository.save(refreshToken);
    }

    @Override
    @Transactional(readOnly = true)
    public RefreshToken verifyActiveToken(String token) {
        RefreshToken refreshToken = refreshTokenRepository.findByTokenAndRevokedFalse(token)
                .orElseThrow(() -> new UnauthorizedException("Refresh token was not found"));

        if (refreshToken.getExpiresAt().isBefore(Instant.now())) {
            throw new UnauthorizedException("Refresh token has expired");
        }

        return refreshToken;
    }

    @Override
    @Transactional
    public void revokeToken(String token) {
        refreshTokenRepository.findByTokenAndRevokedFalse(token).ifPresent(refreshToken -> {
            refreshToken.setRevoked(true);
            refreshTokenRepository.save(refreshToken);
        });
    }

    @Override
    @Transactional
    public void revokeSession(Long sessionId, User currentUser) {
        RefreshToken refreshToken = refreshTokenRepository.findByIdAndUserId(sessionId, currentUser.getId())
                .orElseThrow(() -> new ResourceNotFoundException("Session not found"));
        refreshToken.setRevoked(true);
        refreshTokenRepository.save(refreshToken);
    }

    @Override
    @Transactional
    public void revokeAllSessions(User currentUser) {
        refreshTokenRepository.revokeAllByUserId(currentUser.getId());
    }

    @Override
    @Transactional(readOnly = true)
    public List<SessionResponse> getActiveSessions(User currentUser) {
        return refreshTokenRepository.findAllByUserIdAndRevokedFalseOrderByCreatedAtDesc(currentUser.getId())
                .stream()
                .filter(token -> token.getExpiresAt().isAfter(Instant.now()))
                .map(SessionMapper::toResponse)
                .toList();
    }
}
