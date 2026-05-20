package com.nguyenductien.backend.service.impl;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nguyenductien.backend.dto.command.DeviceCommandRequest;
import com.nguyenductien.backend.dto.command.DeviceCommandResponse;
import com.nguyenductien.backend.entity.Device;
import com.nguyenductien.backend.entity.DeviceCommand;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.enums.CommandStatus;
import com.nguyenductien.backend.exception.BadRequestException;
import com.nguyenductien.backend.mapper.DeviceCommandMapper;
import com.nguyenductien.backend.repository.DeviceCommandRepository;
import com.nguyenductien.backend.service.DeviceCommandService;
import com.nguyenductien.backend.service.DeviceService;
import com.nguyenductien.backend.service.MqttService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class DeviceCommandServiceImpl implements DeviceCommandService {

    private final DeviceCommandRepository deviceCommandRepository;
    private final DeviceService deviceService;
    private final MqttService mqttService;
    private final ObjectMapper objectMapper;

    @Override
    @Transactional
    public DeviceCommandResponse sendCommand(Long deviceId, DeviceCommandRequest request, User currentUser) {
        Device device = deviceService.getAccessibleDevice(deviceId, currentUser);
        String outboundPayload = buildOutboundPayload(request);

        DeviceCommand command = DeviceCommand.builder()
                .device(device)
                .requestedBy(currentUser)
                .commandType(request.commandType().trim())
                .payload(outboundPayload)
                .status(CommandStatus.PENDING)
                .build();

        boolean published = mqttService.publishDeviceCommand(device.getDeviceCode(), outboundPayload);

        if (published) {
            command.setStatus(CommandStatus.SENT);
            command.setResponseMessage("Command published to MQTT broker");
            command.setSentAt(Instant.now());
        } else {
            command.setStatus(CommandStatus.FAILED);
            command.setResponseMessage("Command could not be published to MQTT broker");
        }

        return DeviceCommandMapper.toResponse(deviceCommandRepository.save(command));
    }

    @Override
    @Transactional(readOnly = true)
    public List<DeviceCommandResponse> getDeviceCommands(Long deviceId, User currentUser) {
        Device device = deviceService.getAccessibleDevice(deviceId, currentUser);
        return deviceCommandRepository.findTop50ByDeviceIdOrderByRequestedAtDesc(device.getId())
                .stream()
                .map(DeviceCommandMapper::toResponse)
                .toList();
    }

    private String buildOutboundPayload(DeviceCommandRequest request) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("commandType", request.commandType().trim());
        payload.put("payload", request.payload());

        try {
            return objectMapper.writeValueAsString(payload);
        } catch (JsonProcessingException exception) {
            throw new BadRequestException("Command payload cannot be serialized");
        }
    }
}
