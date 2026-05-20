package com.nguyenductien.backend.mapper;

import com.nguyenductien.backend.dto.device.DeviceResponse;
import com.nguyenductien.backend.entity.Device;

public final class DeviceMapper {

    private DeviceMapper() {
    }

    public static DeviceResponse toResponse(Device device, boolean online) {
        return new DeviceResponse(
                device.getId(),
                device.getName(),
                device.getDeviceCode(),
                device.getDescription(),
                device.getLocation(),
                device.getStatus().name(),
                device.getOwner() != null ? device.getOwner().getId() : null,
                device.getOwner() != null ? device.getOwner().getEmail() : null,
                device.getLastSeenAt(),
                device.getLastKnownState(),
                online,
                device.getCreatedAt()
        );
    }
}
