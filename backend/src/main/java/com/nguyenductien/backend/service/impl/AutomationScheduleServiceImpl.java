package com.nguyenductien.backend.service.impl;

import java.util.List;
import java.util.stream.Collectors;

import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.nguyenductien.backend.dto.automation.AutomationScheduleRequest;
import com.nguyenductien.backend.dto.automation.AutomationScheduleResponse;
import com.nguyenductien.backend.entity.AutomationSchedule;
import com.nguyenductien.backend.entity.Device;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.exception.ResourceNotFoundException;
import com.nguyenductien.backend.mapper.AutomationScheduleMapper;
import com.nguyenductien.backend.repository.AutomationScheduleRepository;
import com.nguyenductien.backend.security.SecurityUtils;
import com.nguyenductien.backend.service.AutomationScheduleService;
import com.nguyenductien.backend.service.DeviceService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class AutomationScheduleServiceImpl implements AutomationScheduleService {

    private final AutomationScheduleRepository automationScheduleRepository;
    private final DeviceService deviceService;

    @Override
    @Transactional(readOnly = true)
    public List<AutomationScheduleResponse> getSchedules(User currentUser) {
        List<AutomationSchedule> schedules = SecurityUtils.isAdmin(currentUser)
                ? automationScheduleRepository.findAll(Sort.by(Sort.Direction.DESC, "createdAt"))
                : automationScheduleRepository.findAllByDeviceOwnerIdOrderByCreatedAtDesc(currentUser.getId());

        return schedules.stream()
                .map(AutomationScheduleMapper::toResponse)
                .toList();
    }

    @Override
    @Transactional
    public AutomationScheduleResponse createSchedule(AutomationScheduleRequest request, User currentUser) {
        Device device = deviceService.getAccessibleDevice(request.deviceId(), currentUser);
        AutomationSchedule schedule = AutomationSchedule.builder()
                .device(device)
                .name(request.name().trim())
                .enabled(request.enabled())
                .targetPower(request.targetPower())
                .timeOfDay(request.timeOfDay())
                .daysOfWeek(serializeDays(request.daysOfWeek()))
                .timezoneOffsetMinutes(request.timezoneOffsetMinutes())
                .build();

        return AutomationScheduleMapper.toResponse(automationScheduleRepository.save(schedule));
    }

    @Override
    @Transactional
    public AutomationScheduleResponse updateSchedule(Long scheduleId, AutomationScheduleRequest request, User currentUser) {
        AutomationSchedule schedule = getAccessibleSchedule(scheduleId, currentUser);
        Device device = deviceService.getAccessibleDevice(request.deviceId(), currentUser);

        schedule.setDevice(device);
        schedule.setName(request.name().trim());
        schedule.setEnabled(request.enabled());
        schedule.setTargetPower(request.targetPower());
        schedule.setTimeOfDay(request.timeOfDay());
        schedule.setDaysOfWeek(serializeDays(request.daysOfWeek()));
        schedule.setTimezoneOffsetMinutes(request.timezoneOffsetMinutes());

        return AutomationScheduleMapper.toResponse(automationScheduleRepository.save(schedule));
    }

    @Override
    @Transactional
    public void deleteSchedule(Long scheduleId, User currentUser) {
        AutomationSchedule schedule = getAccessibleSchedule(scheduleId, currentUser);
        automationScheduleRepository.delete(schedule);
    }

    private AutomationSchedule getAccessibleSchedule(Long scheduleId, User currentUser) {
        AutomationSchedule schedule = automationScheduleRepository.findById(scheduleId)
                .orElseThrow(() -> new ResourceNotFoundException("Automation schedule not found"));

        deviceService.getAccessibleDevice(schedule.getDevice().getId(), currentUser);
        return schedule;
    }

    private String serializeDays(List<Integer> daysOfWeek) {
        return daysOfWeek.stream()
                .distinct()
                .sorted()
                .map(String::valueOf)
                .collect(Collectors.joining(","));
    }
}
