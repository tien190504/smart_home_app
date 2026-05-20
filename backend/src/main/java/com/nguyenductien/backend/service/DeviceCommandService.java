package com.nguyenductien.backend.service;

import java.util.List;

import com.nguyenductien.backend.dto.command.DeviceCommandRequest;
import com.nguyenductien.backend.dto.command.DeviceCommandResponse;
import com.nguyenductien.backend.entity.User;

public interface DeviceCommandService {

    DeviceCommandResponse sendCommand(Long deviceId, DeviceCommandRequest request, User currentUser);

    List<DeviceCommandResponse> getDeviceCommands(Long deviceId, User currentUser);
}
