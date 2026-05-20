package com.nguyenductien.backend.dto.system;

public record SystemDiscoveryResponse(
        String service,
        String applicationName,
        String restBaseUrl,
        String mqttTcpHost,
        int mqttTcpPort,
        String mqttBrokerUrl
) {
}
