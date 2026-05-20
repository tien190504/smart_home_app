package com.nguyenductien.backend.dto.device;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record DeviceProvisionRequest(
        @NotBlank(message = "Device code is required")
        @Size(max = 120, message = "Device code must be at most 120 characters")
        String deviceCode,

        @NotBlank(message = "Pairing code is required")
        @Size(max = 50, message = "Pairing code must be at most 50 characters")
        String pairingCode
) {
}
