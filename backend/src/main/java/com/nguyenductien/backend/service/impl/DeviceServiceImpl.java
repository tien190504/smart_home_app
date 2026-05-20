package com.nguyenductien.backend.service.impl;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.springframework.data.domain.Sort;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import com.nguyenductien.backend.config.DevicePresenceProperties;
import com.nguyenductien.backend.dto.device.DeviceCreateRequest;
import com.nguyenductien.backend.dto.device.DeviceProvisionRequest;
import com.nguyenductien.backend.dto.device.DeviceResponse;
import com.nguyenductien.backend.dto.device.DeviceUpdateRequest;
import com.nguyenductien.backend.entity.Device;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.enums.DeviceStatus;
import com.nguyenductien.backend.exception.BadRequestException;
import com.nguyenductien.backend.exception.ResourceNotFoundException;
import com.nguyenductien.backend.mapper.DeviceMapper;
import com.nguyenductien.backend.repository.DeviceRepository;
import com.nguyenductien.backend.security.SecurityUtils;
import com.nguyenductien.backend.service.DeviceService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class DeviceServiceImpl implements DeviceService {

    private final DeviceRepository deviceRepository;
    private final DevicePresenceProperties devicePresenceProperties;

    @Override
    @Transactional
    public DeviceResponse createDevice(DeviceCreateRequest request, User currentUser) {
        String normalizedDeviceCode = normalize(request.deviceCode());
        String normalizedPairingCode = normalize(request.pairingCode());

        if (deviceRepository.existsByDeviceCodeIgnoreCase(normalizedDeviceCode)) {
            throw new BadRequestException("Device code already exists");
        }

        Device device = Device.builder()
                .name(request.name().trim())
                .deviceCode(normalizedDeviceCode)
                .pairingCode(normalizedPairingCode)
                .description(trimToNull(request.description()))
                .location(trimToNull(request.location()))
                .status(DeviceStatus.PENDING)
                .owner(currentUser)
                .build();

        Device savedDevice = deviceRepository.save(device);
        return DeviceMapper.toResponse(savedDevice, isOnline(savedDevice));
    }

    @Override
    @Transactional
    public DeviceResponse provisionDevice(DeviceProvisionRequest request, User currentUser) {
        Device device = deviceRepository.findByDeviceCodeIgnoreCase(normalize(request.deviceCode()))
                .orElseThrow(() -> new ResourceNotFoundException("Device not found"));

        if (!device.getPairingCode().equalsIgnoreCase(normalize(request.pairingCode()))) {
            throw new BadRequestException("Pairing code is invalid");
        }

        if (device.getOwner() != null && !device.getOwner().getId().equals(currentUser.getId())) {
            throw new BadRequestException("Device is already linked to another user");
        }

        device.setOwner(currentUser);
        if (device.getStatus() != DeviceStatus.DISABLED) {
            refreshOfflineDevice(device, Instant.now());
            if (device.getLastSeenAt() == null) {
                device.setStatus(DeviceStatus.PENDING);
            } else if (device.getStatus() == DeviceStatus.PENDING) {
                device.setStatus(DeviceStatus.OFFLINE);
            }
        }

        Device savedDevice = deviceRepository.save(device);
        return DeviceMapper.toResponse(savedDevice, isOnline(savedDevice));
    }

    @Override
    @Transactional
    public List<DeviceResponse> getDevicesForCurrentUser(User currentUser) {
        List<Device> devices = SecurityUtils.isAdmin(currentUser)
                ? deviceRepository.findAll(Sort.by(Sort.Direction.DESC, "createdAt"))
                : deviceRepository.findAllByOwnerIdOrderByCreatedAtDesc(currentUser.getId());

        Instant now = Instant.now();
        refreshOfflineDevices(devices, now);

        return devices.stream()
                .map(device -> DeviceMapper.toResponse(device, isOnline(device, now)))
                .toList();
    }

    @Override
    @Transactional
    public DeviceResponse getDeviceById(Long deviceId, User currentUser) {
        Device device = getAccessibleDevice(deviceId, currentUser);
        Instant now = Instant.now();
        refreshOfflineDevice(device, now);
        return DeviceMapper.toResponse(device, isOnline(device, now));
    }

    @Override
    @Transactional
    public DeviceResponse updateDevice(Long deviceId, DeviceUpdateRequest request, User currentUser) {
        Device device = getAccessibleDevice(deviceId, currentUser);

        if (StringUtils.hasText(request.name())) {
            device.setName(request.name().trim());
        }
        if (request.description() != null) {
            device.setDescription(trimToNull(request.description()));
        }
        if (request.location() != null) {
            device.setLocation(trimToNull(request.location()));
        }
        if (request.status() != null) {
            device.setStatus(request.status());
        }

        Device savedDevice = deviceRepository.save(device);
        return DeviceMapper.toResponse(savedDevice, isOnline(savedDevice));
    }

    @Override
    @Transactional(readOnly = true)
    public Device getAccessibleDevice(Long deviceId, User currentUser) {
        Device device = deviceRepository.findById(deviceId)
                .orElseThrow(() -> new ResourceNotFoundException("Device not found"));

        if (SecurityUtils.isAdmin(currentUser)) {
            return device;
        }

        if (device.getOwner() == null || !device.getOwner().getId().equals(currentUser.getId())) {
            throw new AccessDeniedException("You do not have access to this device");
        }

        return device;
    }

    @Override
    @Transactional(readOnly = true)
    public Device getDeviceByCode(String deviceCode) {
        return deviceRepository.findByDeviceCodeIgnoreCase(normalize(deviceCode))
                .orElseThrow(() -> new ResourceNotFoundException("Device not found with code: " + deviceCode));
    }

    @Override
    @Transactional
    public void updateHeartbeat(Device device, String lastKnownState) {
        updatePresence(device, lastKnownState, true);
    }

    @Override
    @Transactional
    public void updatePresence(Device device, String lastKnownState, boolean online) {
        if (online) {
            device.setLastSeenAt(Instant.now());
            device.setLastKnownState(lastKnownState);
            if (device.getStatus() != DeviceStatus.DISABLED) {
                device.setStatus(DeviceStatus.ACTIVE);
            }
        } else {
            if (StringUtils.hasText(lastKnownState)) {
                device.setLastKnownState(lastKnownState);
            }
            if (device.getStatus() != DeviceStatus.DISABLED) {
                device.setStatus(device.getLastSeenAt() == null ? DeviceStatus.PENDING : DeviceStatus.OFFLINE);
            }
        }
        deviceRepository.save(device);
    }

    private String normalize(String value) {
        return value.trim().toUpperCase();
    }

    private String trimToNull(String value) {
        if (!StringUtils.hasText(value)) {
            return null;
        }
        return value.trim();
    }

    private void refreshOfflineDevices(List<Device> devices, Instant now) {
        List<Device> staleDevices = new ArrayList<>();
        for (Device device : devices) {
            if (refreshOfflineDevice(device, now)) {
                staleDevices.add(device);
            }
        }

        if (!staleDevices.isEmpty()) {
            deviceRepository.saveAll(staleDevices);
        }
    }

    private boolean refreshOfflineDevice(Device device, Instant now) {
        if (!isPresenceExpired(device, now)) {
            return false;
        }

        device.setStatus(DeviceStatus.OFFLINE);
        return true;
    }

    private boolean isOnline(Device device) {
        return isOnline(device, Instant.now());
    }

    private boolean isOnline(Device device, Instant now) {
        if (device.getStatus() != DeviceStatus.ACTIVE) {
            return false;
        }

        if (device.getLastSeenAt() == null) {
            return false;
        }

        return !isPresenceExpired(device, now);
    }

    private boolean isPresenceExpired(Device device, Instant now) {
        if (device.getStatus() != DeviceStatus.ACTIVE) {
            return false;
        }

        Instant lastSeenAt = device.getLastSeenAt();
        if (lastSeenAt == null) {
            return true;
        }

        Instant cutoff = now.minus(devicePresenceProperties.offlineTimeout());
        return lastSeenAt.isBefore(cutoff);
    }
}
