package com.nguyenductien.backend.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.nguyenductien.backend.dto.automation.AutomationScheduleRequest;
import com.nguyenductien.backend.dto.automation.AutomationScheduleResponse;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.service.AutomationScheduleService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@Validated
@RestController
@RequestMapping("/api/automations")
@RequiredArgsConstructor
public class AutomationScheduleController {

    private final AutomationScheduleService automationScheduleService;

    @GetMapping
    public ResponseEntity<List<AutomationScheduleResponse>> getSchedules(
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(automationScheduleService.getSchedules(currentUser));
    }

    @PostMapping
    public ResponseEntity<AutomationScheduleResponse> createSchedule(
            @Valid @RequestBody AutomationScheduleRequest request,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(automationScheduleService.createSchedule(request, currentUser));
    }

    @PutMapping("/{scheduleId}")
    public ResponseEntity<AutomationScheduleResponse> updateSchedule(
            @PathVariable Long scheduleId,
            @Valid @RequestBody AutomationScheduleRequest request,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(automationScheduleService.updateSchedule(scheduleId, request, currentUser));
    }

    @DeleteMapping("/{scheduleId}")
    public ResponseEntity<Void> deleteSchedule(
            @PathVariable Long scheduleId,
            @AuthenticationPrincipal User currentUser
    ) {
        automationScheduleService.deleteSchedule(scheduleId, currentUser);
        return ResponseEntity.noContent().build();
    }
}
