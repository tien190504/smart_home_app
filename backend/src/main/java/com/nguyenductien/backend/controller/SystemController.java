package com.nguyenductien.backend.controller;

import java.net.URI;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import com.nguyenductien.backend.config.MqttProperties;
import com.nguyenductien.backend.dto.system.SystemDiscoveryResponse;

import lombok.RequiredArgsConstructor;

@RestController
@RequestMapping("/api/system")
@RequiredArgsConstructor
public class SystemController {

    private static final int DEFAULT_MQTT_TCP_PORT = 1883;

    private final MqttProperties mqttProperties;

    @GetMapping("/discovery")
    public ResponseEntity<SystemDiscoveryResponse> discovery() {
        String restBaseUrl = ServletUriComponentsBuilder
                .fromCurrentContextPath()
                .replacePath(null)
                .replaceQuery(null)
                .build()
                .toUriString();

        URI requestUri = URI.create(restBaseUrl);
        String mqttHost = requestUri.getHost();
        int mqttPort = resolveMqttTcpPort(mqttProperties.brokerUrl());

        return ResponseEntity.ok(new SystemDiscoveryResponse(
                "smartify-backend",
                "backend",
                restBaseUrl,
                mqttHost,
                mqttPort,
                "mqtt://" + mqttHost + ":" + mqttPort
        ));
    }

    private int resolveMqttTcpPort(String brokerUrl) {
        if (brokerUrl == null || brokerUrl.isBlank()) {
            return DEFAULT_MQTT_TCP_PORT;
        }

        try {
            URI uri = URI.create(brokerUrl.trim());
            return uri.getPort() > 0 ? uri.getPort() : DEFAULT_MQTT_TCP_PORT;
        } catch (IllegalArgumentException ignored) {
            return DEFAULT_MQTT_TCP_PORT;
        }
    }
}
