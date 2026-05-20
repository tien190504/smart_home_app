package com.nguyenductien.backend.dto.command;

import java.util.Map;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record DeviceCommandRequest(
        @NotBlank(message = "Command type is required")
        String commandType,

        @NotNull(message = "Command payload is required")
        Map<String, Object> payload
) {
}
