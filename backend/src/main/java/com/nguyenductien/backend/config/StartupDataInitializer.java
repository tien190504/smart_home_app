package com.nguyenductien.backend.config;

import java.util.Set;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import com.nguyenductien.backend.entity.Role;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.enums.RoleName;
import com.nguyenductien.backend.repository.RoleRepository;
import com.nguyenductien.backend.repository.UserRepository;

import lombok.RequiredArgsConstructor;

@Component
@RequiredArgsConstructor
public class StartupDataInitializer implements ApplicationRunner {

    private final RoleRepository roleRepository;
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final BootstrapAdminProperties bootstrapAdminProperties;

    @Override
    public void run(ApplicationArguments args) {
        Role userRole = roleRepository.findByName(RoleName.ROLE_USER)
                .orElseGet(() -> roleRepository.save(Role.builder()
                        .name(RoleName.ROLE_USER)
                        .description("Default role for regular users")
                        .build()));

        Role adminRole = roleRepository.findByName(RoleName.ROLE_ADMIN)
                .orElseGet(() -> roleRepository.save(Role.builder()
                        .name(RoleName.ROLE_ADMIN)
                        .description("Full system administration role")
                        .build()));

        if (!StringUtils.hasText(bootstrapAdminProperties.adminEmail())
                || !StringUtils.hasText(bootstrapAdminProperties.adminPassword())
                || !StringUtils.hasText(bootstrapAdminProperties.adminFullName())) {
            return;
        }

        if (!userRepository.existsByEmailIgnoreCase(bootstrapAdminProperties.adminEmail())) {
            User admin = User.builder()
                    .fullName(bootstrapAdminProperties.adminFullName())
                    .email(bootstrapAdminProperties.adminEmail())
                    .password(passwordEncoder.encode(bootstrapAdminProperties.adminPassword()))
                    .enabled(true)
                    .roles(Set.of(adminRole, userRole))
                    .build();
            userRepository.save(admin);
        }
    }
}
