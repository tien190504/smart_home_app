package com.nguyenductien.backend.dto.automation;

import java.util.List;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record AutomationScheduleRequest(
        @NotBlank(message = "Schedule name is required")
        @Size(max = 160, message = "Schedule name must be at most 160 characters")
        String name,

        @NotNull(message = "Device is required")
        Long deviceId,

        boolean enabled,

        boolean targetPower,

        @NotBlank(message = "Time is required")
        @Pattern(
                regexp = "^([01]\\d|2[0-3]):[0-5]\\d$",
                message = "Time must be in HH:mm format"
        )
        String timeOfDay,

        @NotEmpty(message = "At least one day must be selected")
        @Size(max = 7, message = "No more than seven days can be selected")
        List<@Min(value = 1, message = "Days must be between 1 and 7")
             @Max(value = 7, message = "Days must be between 1 and 7") Integer> daysOfWeek,

        @Min(value = -720, message = "Timezone offset is out of range")
        @Max(value = 840, message = "Timezone offset is out of range")
        int timezoneOffsetMinutes
) {
}
