package com.nguyenductien.backend.service;

import com.nguyenductien.backend.dto.auth.AuthResponse;
import com.nguyenductien.backend.dto.auth.LoginRequest;
import com.nguyenductien.backend.dto.auth.RegisterRequest;
import com.nguyenductien.backend.dto.auth.TokenRefreshRequest;

public interface AuthService {

    AuthResponse register(RegisterRequest request, String ipAddress, String deviceInfo);

    AuthResponse login(LoginRequest request, String ipAddress, String deviceInfo);

    AuthResponse refresh(TokenRefreshRequest request, String ipAddress, String deviceInfo);

    void logout(String refreshToken);
}
