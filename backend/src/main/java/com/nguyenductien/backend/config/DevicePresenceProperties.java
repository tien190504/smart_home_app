package com.nguyenductien.backend.config;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.devices")
public record DevicePresenceProperties(long offlineTimeoutMs) {

    public Duration offlineTimeout() {
        long timeoutMs = offlineTimeoutMs > 0 ? offlineTimeoutMs : 30000L;
        return Duration.ofMillis(timeoutMs);
    }
}
