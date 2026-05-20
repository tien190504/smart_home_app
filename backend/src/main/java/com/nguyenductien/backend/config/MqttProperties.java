package com.nguyenductien.backend.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.mqtt")
public record MqttProperties(
        boolean enabled,
        String brokerUrl,
        String clientId,
        String username,
        String password,
        String telemetryTopic,
        String statusTopic,
        String commandTopicTemplate,
        int qos,
        long completionTimeout
) {
}
