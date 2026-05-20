package com.nguyenductien.backend.service;

import java.util.List;

import com.nguyenductien.backend.dto.telemetry.TelemetryResponse;
import com.nguyenductien.backend.entity.User;

public interface TelemetryRecordService {

    void processTelemetryMessage(String topic, String payload);

    List<TelemetryResponse> getTelemetryHistory(Long deviceId, User currentUser);

    TelemetryResponse getLatestTelemetry(Long deviceId, User currentUser);
}
