package com.nguyenductien.backend.mapper;

import java.util.Arrays;
import java.util.List;

import org.springframework.util.StringUtils;

import com.nguyenductien.backend.dto.automation.AutomationScheduleResponse;
import com.nguyenductien.backend.entity.AutomationSchedule;

public final class AutomationScheduleMapper {

    private AutomationScheduleMapper() {
    }

    public static AutomationScheduleResponse toResponse(AutomationSchedule schedule) {
        return new AutomationScheduleResponse(
                schedule.getId(),
                schedule.getName(),
                schedule.isEnabled(),
                schedule.isTargetPower(),
                schedule.getTimeOfDay(),
                parseDays(schedule.getDaysOfWeek()),
                schedule.getTimezoneOffsetMinutes(),
                schedule.getLastTriggeredAt(),
                schedule.getDevice().getId(),
                schedule.getDevice().getName(),
                schedule.getDevice().getDeviceCode(),
                schedule.getDevice().getLocation(),
                schedule.getCreatedAt(),
                schedule.getUpdatedAt()
        );
    }

    public static List<Integer> parseDays(String rawDays) {
        if (!StringUtils.hasText(rawDays)) {
            return List.of();
        }

        return Arrays.stream(rawDays.split(","))
                .map(String::trim)
                .filter(StringUtils::hasText)
                .map(Integer::parseInt)
                .distinct()
                .sorted()
                .toList();
    }
}
