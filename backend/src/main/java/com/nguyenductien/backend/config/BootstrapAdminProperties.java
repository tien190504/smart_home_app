package com.nguyenductien.backend.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.bootstrap")
public record BootstrapAdminProperties(
        String adminFullName,
        String adminEmail,
        String adminPassword
) {
}
