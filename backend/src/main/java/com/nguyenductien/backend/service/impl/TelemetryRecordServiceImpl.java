package com.nguyenductien.backend.service.impl;

import java.io.IOException;
import java.time.Instant;
import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nguyenductien.backend.dto.telemetry.TelemetryResponse;
import com.nguyenductien.backend.entity.Device;
import com.nguyenductien.backend.entity.TelemetryRecord;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.exception.ResourceNotFoundException;
import com.nguyenductien.backend.mapper.TelemetryMapper;
import com.nguyenductien.backend.repository.TelemetryRecordRepository;
import com.nguyenductien.backend.service.DeviceService;
import com.nguyenductien.backend.service.TelemetryRecordService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class TelemetryRecordServiceImpl implements TelemetryRecordService {

    private final TelemetryRecordRepository telemetryRecordRepository;
    private final DeviceService deviceService;
    private final ObjectMapper objectMapper;

    @Override
    @Transactional
    public void processTelemetryMessage(String topic, String payload) {
        String deviceCode = extractDeviceCode(topic);
        if (deviceCode == null) {
            log.warn("Cannot resolve device code from MQTT topic: {}", topic);
            return;
        }

        try {
            Device device = deviceService.getDeviceByCode(deviceCode);
            JsonNode root = objectMapper.readTree(payload);
            String statePayload = resolveStatePayload(root, payload);
            boolean online = resolveOnline(root, true);

            if (isTelemetryTopic(topic)) {
                TelemetryRecord telemetryRecord = TelemetryRecord.builder()
                        .device(device)
                        .temperature(readNumeric(root, "temperature", "temp"))
                        .humidity(readNumeric(root, "humidity"))
                        .batteryLevel(readNumeric(root, "batteryLevel", "battery", "battery_level"))
                        .statePayload(statePayload)
                        .rawPayload(payload)
                        .recordedAt(Instant.now())
                        .build();

                telemetryRecordRepository.save(telemetryRecord);
                deviceService.updatePresence(device, telemetryRecord.getStatePayload(), online);
                log.info("Telemetry saved for device {}", deviceCode);
                return;
            }

            if (isStatusTopic(topic)) {
                deviceService.updatePresence(device, statePayload, online);
                log.info("Device status updated for device {}", deviceCode);
                return;
            }

            log.debug("Ignoring unsupported MQTT topic {}", topic);
        } catch (ResourceNotFoundException exception) {
            log.warn("Received MQTT device message for unknown device {}: {}", deviceCode, exception.getMessage());
        } catch (IOException exception) {
            log.error("Failed to parse MQTT payload for device {}: {}", deviceCode, exception.getMessage());
        }
    }

    @Override
    @Transactional(readOnly = true)
    public List<TelemetryResponse> getTelemetryHistory(Long deviceId, User currentUser) {
        Device device = deviceService.getAccessibleDevice(deviceId, currentUser);
        return telemetryRecordRepository.findTop50ByDeviceIdOrderByRecordedAtDesc(device.getId())
                .stream()
                .map(TelemetryMapper::toResponse)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public TelemetryResponse getLatestTelemetry(Long deviceId, User currentUser) {
        Device device = deviceService.getAccessibleDevice(deviceId, currentUser);
        TelemetryRecord telemetryRecord = telemetryRecordRepository.findFirstByDeviceIdOrderByRecordedAtDesc(device.getId())
                .orElseThrow(() -> new ResourceNotFoundException("Telemetry not found for device"));
        return TelemetryMapper.toResponse(telemetryRecord);
    }

    private String extractDeviceCode(String topic) {
        if (topic == null) {
            return null;
        }

        String[] segments = topic.split("/");
        if (segments.length < 4) {
            return null;
        }
        return segments[2];
    }

    private boolean isTelemetryTopic(String topic) {
        return topic != null && topic.endsWith("/telemetry");
    }

    private boolean isStatusTopic(String topic) {
        return topic != null && topic.endsWith("/status");
    }

    private Double readNumeric(JsonNode node, String... fieldNames) {
        for (String fieldName : fieldNames) {
            JsonNode child = node.get(fieldName);
            if (child == null || child.isNull()) {
                continue;
            }

            if (child.isNumber()) {
                return child.asDouble();
            }

            if (child.isTextual()) {
                try {
                    return Double.parseDouble(child.asText());
                } catch (NumberFormatException ignored) {
                    log.debug("Cannot parse field {} as number", fieldName);
                }
            }
        }
        return null;
    }

    private String resolveStatePayload(JsonNode root, String rawPayload) {
        JsonNode stateNode = root.get("state");
        if (stateNode == null || stateNode.isNull()) {
            return rawPayload;
        }
        return stateNode.toString();
    }

    private boolean resolveOnline(JsonNode root, boolean defaultValue) {
        JsonNode onlineNode = root.get("online");
        if (onlineNode != null && !onlineNode.isNull()) {
            if (onlineNode.isBoolean()) {
                return onlineNode.asBoolean();
            }
            if (onlineNode.isNumber()) {
                return onlineNode.asInt() != 0;
            }
            if (onlineNode.isTextual()) {
                String value = onlineNode.asText("").trim().toLowerCase();
                if ("false".equals(value) || "0".equals(value) || "offline".equals(value)) {
                    return false;
                }
                if ("true".equals(value) || "1".equals(value) || "online".equals(value)) {
                    return true;
                }
            }
        }

        JsonNode statusNode = root.get("status");
        if (statusNode != null && statusNode.isTextual()) {
            String value = statusNode.asText("").trim().toUpperCase();
            if ("OFFLINE".equals(value) || "INACTIVE".equals(value)) {
                return false;
            }
            if ("ACTIVE".equals(value) || "ONLINE".equals(value)) {
                return true;
            }
        }

        JsonNode stateNode = root.get("state");
        if (stateNode != null && stateNode.isObject()) {
            return resolveOnline(stateNode, defaultValue);
        }

        return defaultValue;
    }
}
