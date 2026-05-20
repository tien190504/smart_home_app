package com.nguyenductien.backend.dto.assistant;

public record AssistantActionResponse(
        Long deviceId,
        String deviceCode,
        String deviceName,
        String roomLabel,
        Boolean targetPower,
        boolean success,
        String status,
        String message
) {
}
