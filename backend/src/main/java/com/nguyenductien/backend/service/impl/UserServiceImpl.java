package com.nguyenductien.backend.service.impl;

import java.util.List;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.nguyenductien.backend.dto.auth.UserResponse;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.mapper.UserMapper;
import com.nguyenductien.backend.repository.UserRepository;
import com.nguyenductien.backend.security.SecurityUtils;
import com.nguyenductien.backend.service.UserService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;

    @Override
    @Transactional(readOnly = true)
    public UserResponse getCurrentUser(User currentUser) {
        return UserMapper.toResponse(currentUser);
    }

    @Override
    @Transactional(readOnly = true)
    public List<UserResponse> getAllUsers(User currentUser) {
        if (!SecurityUtils.isAdmin(currentUser)) {
            throw new AccessDeniedException("Only administrators can view all users");
        }

        return userRepository.findAllByOrderByCreatedAtDesc()
                .stream()
                .map(UserMapper::toResponse)
                .toList();
    }
}
