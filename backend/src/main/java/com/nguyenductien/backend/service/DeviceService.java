package com.nguyenductien.backend.service;

import java.util.List;

import com.nguyenductien.backend.dto.device.DeviceCreateRequest;
import com.nguyenductien.backend.dto.device.DeviceProvisionRequest;
import com.nguyenductien.backend.dto.device.DeviceResponse;
import com.nguyenductien.backend.dto.device.DeviceUpdateRequest;
import com.nguyenductien.backend.entity.Device;
import com.nguyenductien.backend.entity.User;

public interface DeviceService {

    DeviceResponse createDevice(DeviceCreateRequest request, User currentUser);

    DeviceResponse provisionDevice(DeviceProvisionRequest request, User currentUser);

    List<DeviceResponse> getDevicesForCurrentUser(User currentUser);

    DeviceResponse getDeviceById(Long deviceId, User currentUser);

    DeviceResponse updateDevice(Long deviceId, DeviceUpdateRequest request, User currentUser);

    Device getAccessibleDevice(Long deviceId, User currentUser);

    Device getDeviceByCode(String deviceCode);

    void updateHeartbeat(Device device, String lastKnownState);

    void updatePresence(Device device, String lastKnownState, boolean online);
}
