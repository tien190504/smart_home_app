package com.nguyenductien.backend.dto.device;

import com.nguyenductien.backend.enums.DeviceStatus;

import jakarta.validation.constraints.Size;

public record DeviceUpdateRequest(
        @Size(max = 120, message = "Device name must be at most 120 characters")
        String name,

        @Size(max = 500, message = "Description must be at most 500 characters")
        String description,

        @Size(max = 255, message = "Location must be at most 255 characters")
        String location,

        DeviceStatus status
) {
}
