package com.nguyenductien.backend.security;

import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.enums.RoleName;

public final class SecurityUtils {

    private SecurityUtils() {
    }

    public static boolean hasRole(User user, RoleName roleName) {
        return user.getRoles().stream().anyMatch(role -> role.getName() == roleName);
    }

    public static boolean isAdmin(User user) {
        return hasRole(user, RoleName.ROLE_ADMIN);
    }
}
