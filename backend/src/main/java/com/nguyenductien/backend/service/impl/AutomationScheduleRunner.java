package com.nguyenductien.backend.service.impl;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Sort;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nguyenductien.backend.entity.AutomationSchedule;
import com.nguyenductien.backend.enums.DeviceStatus;
import com.nguyenductien.backend.mapper.AutomationScheduleMapper;
import com.nguyenductien.backend.repository.AutomationScheduleRepository;
import com.nguyenductien.backend.service.MqttService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class AutomationScheduleRunner {

    private static final DateTimeFormatter TIME_FORMATTER = DateTimeFormatter.ofPattern("HH:mm");

    private final AutomationScheduleRepository automationScheduleRepository;
    private final MqttService mqttService;
    private final ObjectMapper objectMapper;

    @Value("${app.automation.poll-interval-ms:15000}")
    private long pollIntervalMs;

    @Scheduled(
            fixedDelayString = "${app.automation.poll-interval-ms:15000}",
            initialDelayString = "${app.automation.poll-interval-ms:15000}"
    )
    @Transactional
    public void processDueSchedules() {
        if (!mqttService.isEnabled()) {
            return;
        }

        Instant now = Instant.now();
        List<AutomationSchedule> schedules = automationScheduleRepository.findAllByEnabledTrue(Sort.by("createdAt"));

        for (AutomationSchedule schedule : schedules) {
            if (!shouldTrigger(schedule, now)) {
                continue;
            }

            String payload = buildPayload(schedule.isTargetPower());
            boolean published = mqttService.publishDeviceCommand(schedule.getDevice().getDeviceCode(), payload);
            if (!published) {
                log.warn("Automation {} could not publish a command for device {}", schedule.getId(),
                        schedule.getDevice().getDeviceCode());
                continue;
            }

            schedule.setLastTriggeredAt(now);
            log.info("Automation {} triggered for device {} at {}", schedule.getId(),
                    schedule.getDevice().getDeviceCode(), schedule.getTimeOfDay());
        }
    }

    private boolean shouldTrigger(AutomationSchedule schedule, Instant now) {
        if (schedule.getDevice().getOwner() == null) {
            return false;
        }
        if (schedule.getDevice().getStatus() == DeviceStatus.DISABLED) {
            return false;
        }

        ZoneOffset offset = ZoneOffset.ofTotalSeconds(schedule.getTimezoneOffsetMinutes() * 60);
        OffsetDateTime localNow = now.atOffset(offset);
        if (!schedule.getTimeOfDay().equals(TIME_FORMATTER.format(localNow))) {
            return false;
        }

        List<Integer> days = AutomationScheduleMapper.parseDays(schedule.getDaysOfWeek());
        if (!days.contains(localNow.getDayOfWeek().getValue())) {
            return false;
        }

        Instant lastTriggeredAt = schedule.getLastTriggeredAt();
        if (lastTriggeredAt == null) {
            return true;
        }

        OffsetDateTime lastLocal = lastTriggeredAt.atOffset(offset).truncatedTo(ChronoUnit.MINUTES);
        OffsetDateTime currentSlot = localNow.truncatedTo(ChronoUnit.MINUTES);
        if (!lastLocal.isBefore(currentSlot)) {
            return false;
        }

        long secondsSinceLastTrigger = ChronoUnit.SECONDS.between(lastTriggeredAt, now);
        return secondsSinceLastTrigger >= Math.max(15L, pollIntervalMs / 1000L);
    }

    private String buildPayload(boolean targetPower) {
        Map<String, Object> outbound = new LinkedHashMap<>();
        outbound.put("commandType", "set_state");
        outbound.put("payload", Map.of("power", targetPower));
        try {
            return objectMapper.writeValueAsString(outbound);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Automation payload could not be serialized", exception);
        }
    }
}
