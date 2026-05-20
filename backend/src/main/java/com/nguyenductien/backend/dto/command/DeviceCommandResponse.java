package com.nguyenductien.backend.dto.command;

import java.time.Instant;

public record DeviceCommandResponse(
        Long id,
        Long deviceId,
        String deviceCode,
        String commandType,
        String payload,
        String status,
        String responseMessage,
        Long requestedById,
        Instant requestedAt,
        Instant sentAt
) {
}
