package com.nguyenductien.backend.mqtt;

import org.springframework.stereotype.Component;

import com.nguyenductien.backend.service.TelemetryRecordService;

import lombok.RequiredArgsConstructor;

@Component
@RequiredArgsConstructor
public class MqttTelemetryListener {

    private final TelemetryRecordService telemetryRecordService;

    public void handleTelemetry(String topic, String payload) {
        telemetryRecordService.processTelemetryMessage(topic, payload);
    }
}
