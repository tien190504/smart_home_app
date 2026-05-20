package com.nguyenductien.backend.mapper;

import com.nguyenductien.backend.dto.auth.RoleResponse;
import com.nguyenductien.backend.entity.Role;

public final class RoleMapper {

    private RoleMapper() {
    }

    public static RoleResponse toResponse(Role role) {
        return new RoleResponse(role.getId(), role.getName().name(), role.getDescription());
    }
}
