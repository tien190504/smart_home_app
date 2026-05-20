package com.nguyenductien.backend.mapper;

import com.nguyenductien.backend.dto.auth.UserResponse;
import com.nguyenductien.backend.entity.User;

public final class UserMapper {

    private UserMapper() {
    }

    public static UserResponse toResponse(User user) {
        return new UserResponse(
                user.getId(),
                user.getFullName(),
                user.getEmail(),
                user.isEnabled(),
                user.getRoles().stream().map(role -> role.getName().name()).collect(java.util.stream.Collectors.toSet()),
                user.getCreatedAt()
        );
    }
}
