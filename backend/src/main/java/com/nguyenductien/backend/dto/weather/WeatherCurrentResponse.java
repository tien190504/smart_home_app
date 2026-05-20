package com.nguyenductien.backend.dto.weather;

import java.time.Instant;

public record WeatherCurrentResponse(
        double latitude,
        double longitude,
        String timezone,
        double temperatureC,
        Double apparentTemperatureC,
        Integer humidityPercent,
        String condition,
        String iconKey,
        Instant observedAt
) {
}
