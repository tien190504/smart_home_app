package com.nguyenductien.backend.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.assistant")
public record AssistantProperties(
        String geminiApiKey,
        String geminiModel
) {

    public boolean configured() {
        return geminiApiKey != null && !geminiApiKey.isBlank();
    }

    public String resolvedModel() {
        return geminiModel == null || geminiModel.isBlank()
                ? "gemini-2.5-flash"
                : geminiModel.trim();
    }
}
