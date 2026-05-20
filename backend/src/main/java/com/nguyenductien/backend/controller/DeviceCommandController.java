package com.nguyenductien.backend.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.nguyenductien.backend.dto.command.DeviceCommandRequest;
import com.nguyenductien.backend.dto.command.DeviceCommandResponse;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.service.DeviceCommandService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@Validated
@RestController
@RequestMapping("/api/commands")
@RequiredArgsConstructor
public class DeviceCommandController {

    private final DeviceCommandService deviceCommandService;

    @PostMapping("/devices/{deviceId}")
    public ResponseEntity<DeviceCommandResponse> sendCommand(
            @PathVariable Long deviceId,
            @Valid @RequestBody DeviceCommandRequest request,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(deviceCommandService.sendCommand(deviceId, request, currentUser));
    }

    @GetMapping("/devices/{deviceId}")
    public ResponseEntity<List<DeviceCommandResponse>> getDeviceCommands(
            @PathVariable Long deviceId,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(deviceCommandService.getDeviceCommands(deviceId, currentUser));
    }
}
