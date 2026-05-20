package com.nguyenductien.backend.mapper;

import com.nguyenductien.backend.dto.auth.SessionResponse;
import com.nguyenductien.backend.entity.RefreshToken;

public final class SessionMapper {

    private SessionMapper() {
    }

    public static SessionResponse toResponse(RefreshToken refreshToken) {
        return new SessionResponse(
                refreshToken.getId(),
                refreshToken.getDeviceInfo(),
                refreshToken.getIpAddress(),
                refreshToken.getCreatedAt(),
                refreshToken.getExpiresAt(),
                Boolean.TRUE.equals(refreshToken.getRevoked())
        );
    }
}
