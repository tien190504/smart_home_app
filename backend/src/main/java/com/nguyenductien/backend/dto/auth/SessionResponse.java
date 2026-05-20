package com.nguyenductien.backend.dto.auth;

import java.time.Instant;

public record SessionResponse(
        Long id,
        String deviceInfo,
        String ipAddress,
        Instant createdAt,
        Instant expiresAt,
        boolean revoked
) {
}
