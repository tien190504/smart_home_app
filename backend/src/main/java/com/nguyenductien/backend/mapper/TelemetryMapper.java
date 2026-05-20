package com.nguyenductien.backend.mapper;

import com.nguyenductien.backend.dto.telemetry.TelemetryResponse;
import com.nguyenductien.backend.entity.TelemetryRecord;

public final class TelemetryMapper {

    private TelemetryMapper() {
    }

    public static TelemetryResponse toResponse(TelemetryRecord record) {
        return new TelemetryResponse(
                record.getId(),
                record.getDevice().getId(),
                record.getTemperature(),
                record.getHumidity(),
                record.getBatteryLevel(),
                record.getStatePayload(),
                record.getRawPayload(),
                record.getRecordedAt()
        );
    }
}
