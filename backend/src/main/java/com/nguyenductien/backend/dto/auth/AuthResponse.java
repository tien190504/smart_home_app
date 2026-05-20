package com.nguyenductien.backend.dto.auth;

public record AuthResponse(
        String accessToken,
        long accessTokenExpiresInMs,
        String refreshToken,
        long refreshTokenExpiresInMs,
        UserResponse user
) {
}
