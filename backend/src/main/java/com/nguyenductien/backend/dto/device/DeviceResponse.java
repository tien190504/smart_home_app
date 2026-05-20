package com.nguyenductien.backend.dto.device;

import java.time.Instant;

public record DeviceResponse(
        Long id,
        String name,
        String deviceCode,
        String description,
        String location,
        String status,
        Long ownerId,
        String ownerEmail,
        Instant lastSeenAt,
        String lastKnownState,
        boolean online,
        Instant createdAt
) {
}
