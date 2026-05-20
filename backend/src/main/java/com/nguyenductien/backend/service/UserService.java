package com.nguyenductien.backend.service;

import java.util.List;

import com.nguyenductien.backend.dto.auth.UserResponse;
import com.nguyenductien.backend.entity.User;

public interface UserService {

    UserResponse getCurrentUser(User currentUser);

    List<UserResponse> getAllUsers(User currentUser);
}
