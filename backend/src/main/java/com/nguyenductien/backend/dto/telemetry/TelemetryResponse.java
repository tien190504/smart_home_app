package com.nguyenductien.backend.dto.telemetry;

import java.time.Instant;

public record TelemetryResponse(
        Long id,
        Long deviceId,
        Double temperature,
        Double humidity,
        Double batteryLevel,
        String statePayload,
        String rawPayload,
        Instant recordedAt
) {
}
