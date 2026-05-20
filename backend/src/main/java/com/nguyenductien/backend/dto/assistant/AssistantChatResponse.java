package com.nguyenductien.backend.dto.assistant;

import java.util.List;

import com.nguyenductien.backend.dto.weather.WeatherCurrentResponse;

public record AssistantChatResponse(
        String reply,
        String mode,
        List<AssistantActionResponse> actions,
        WeatherCurrentResponse weather
) {
}
