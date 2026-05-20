package com.nguyenductien.backend.mapper;

import com.nguyenductien.backend.dto.command.DeviceCommandResponse;
import com.nguyenductien.backend.entity.DeviceCommand;

public final class DeviceCommandMapper {

    private DeviceCommandMapper() {
    }

    public static DeviceCommandResponse toResponse(DeviceCommand deviceCommand) {
        return new DeviceCommandResponse(
                deviceCommand.getId(),
                deviceCommand.getDevice().getId(),
                deviceCommand.getDevice().getDeviceCode(),
                deviceCommand.getCommandType(),
                deviceCommand.getPayload(),
                deviceCommand.getStatus().name(),
                deviceCommand.getResponseMessage(),
                deviceCommand.getRequestedBy().getId(),
                deviceCommand.getRequestedAt(),
                deviceCommand.getSentAt()
        );
    }
}
