package com.nguyenductien.backend.dto.assistant;

import jakarta.validation.constraints.NotBlank;

public record AssistantChatRequest(
        @NotBlank(message = "Message is required")
        String message,
        Double latitude,
        Double longitude
) {
}
