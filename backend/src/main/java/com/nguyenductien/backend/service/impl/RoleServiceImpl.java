package com.nguyenductien.backend.service.impl;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.nguyenductien.backend.dto.auth.RoleResponse;
import com.nguyenductien.backend.mapper.RoleMapper;
import com.nguyenductien.backend.repository.RoleRepository;
import com.nguyenductien.backend.service.RoleService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class RoleServiceImpl implements RoleService {

    private final RoleRepository roleRepository;

    @Override
    @Transactional(readOnly = true)
    public List<RoleResponse> getAllRoles() {
        return roleRepository.findAllByOrderByNameAsc()
                .stream()
                .map(RoleMapper::toResponse)
                .toList();
    }
}
