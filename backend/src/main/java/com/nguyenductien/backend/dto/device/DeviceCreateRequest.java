package com.nguyenductien.backend.dto.device;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record DeviceCreateRequest(
        @NotBlank(message = "Device name is required")
        @Size(max = 120, message = "Device name must be at most 120 characters")
        String name,

        @NotBlank(message = "Device code is required")
        @Size(max = 120, message = "Device code must be at most 120 characters")
        String deviceCode,

        @NotBlank(message = "Pairing code is required")
        @Size(max = 50, message = "Pairing code must be at most 50 characters")
        String pairingCode,

        @Size(max = 500, message = "Description must be at most 500 characters")
        String description,

        @Size(max = 255, message = "Location must be at most 255 characters")
        String location
) {
}
