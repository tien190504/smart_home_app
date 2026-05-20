package com.nguyenductien.backend.service;

import java.util.List;

import com.nguyenductien.backend.dto.auth.RoleResponse;

public interface RoleService {

    List<RoleResponse> getAllRoles();
}
