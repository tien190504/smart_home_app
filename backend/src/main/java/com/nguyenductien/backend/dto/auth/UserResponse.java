package com.nguyenductien.backend.dto.auth;

import java.time.Instant;
import java.util.Set;

public record UserResponse(
        Long id,
        String fullName,
        String email,
        boolean enabled,
        Set<String> roles,
        Instant createdAt
) {
}
