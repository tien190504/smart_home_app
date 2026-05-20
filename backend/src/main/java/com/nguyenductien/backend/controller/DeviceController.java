package com.nguyenductien.backend.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.nguyenductien.backend.dto.device.DeviceCreateRequest;
import com.nguyenductien.backend.dto.device.DeviceProvisionRequest;
import com.nguyenductien.backend.dto.device.DeviceResponse;
import com.nguyenductien.backend.dto.device.DeviceUpdateRequest;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.service.DeviceService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@Validated
@RestController
@RequestMapping("/api/devices")
@RequiredArgsConstructor
public class DeviceController {

    private final DeviceService deviceService;

    @PostMapping
    public ResponseEntity<DeviceResponse> createDevice(
            @Valid @RequestBody DeviceCreateRequest request,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(deviceService.createDevice(request, currentUser));
    }

    @PostMapping("/provision")
    public ResponseEntity<DeviceResponse> provisionDevice(
            @Valid @RequestBody DeviceProvisionRequest request,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(deviceService.provisionDevice(request, currentUser));
    }

    @GetMapping
    public ResponseEntity<List<DeviceResponse>> getDevices(@AuthenticationPrincipal User currentUser) {
        return ResponseEntity.ok(deviceService.getDevicesForCurrentUser(currentUser));
    }

    @GetMapping("/{deviceId}")
    public ResponseEntity<DeviceResponse> getDevice(
            @PathVariable Long deviceId,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(deviceService.getDeviceById(deviceId, currentUser));
    }

    @PutMapping("/{deviceId}")
    public ResponseEntity<DeviceResponse> updateDevice(
            @PathVariable Long deviceId,
            @Valid @RequestBody DeviceUpdateRequest request,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(deviceService.updateDevice(deviceId, request, currentUser));
    }
}
