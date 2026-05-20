package com.nguyenductien.backend.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.nguyenductien.backend.dto.telemetry.TelemetryResponse;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.service.TelemetryRecordService;

import lombok.RequiredArgsConstructor;

@RestController
@RequestMapping("/api/telemetry")
@RequiredArgsConstructor
public class TelemetryRecordController {

    private final TelemetryRecordService telemetryRecordService;

    @GetMapping("/devices/{deviceId}")
    public ResponseEntity<List<TelemetryResponse>> getTelemetryHistory(
            @PathVariable Long deviceId,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(telemetryRecordService.getTelemetryHistory(deviceId, currentUser));
    }

    @GetMapping("/devices/{deviceId}/latest")
    public ResponseEntity<TelemetryResponse> getLatestTelemetry(
            @PathVariable Long deviceId,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(telemetryRecordService.getLatestTelemetry(deviceId, currentUser));
    }
}
