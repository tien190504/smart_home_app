package com.nguyenductien.backend.dto.automation;

import java.time.Instant;
import java.util.List;

public record AutomationScheduleResponse(
        Long id,
        String name,
        boolean enabled,
        boolean targetPower,
        String timeOfDay,
        List<Integer> daysOfWeek,
        int timezoneOffsetMinutes,
        Instant lastTriggeredAt,
        Long deviceId,
        String deviceName,
        String deviceCode,
        String deviceLocation,
        Instant createdAt,
        Instant updatedAt
) {
}
