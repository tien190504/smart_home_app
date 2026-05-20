package com.nguyenductien.backend.service.impl;

import java.util.Set;

import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.nguyenductien.backend.dto.auth.AuthResponse;
import com.nguyenductien.backend.dto.auth.LoginRequest;
import com.nguyenductien.backend.dto.auth.RegisterRequest;
import com.nguyenductien.backend.dto.auth.TokenRefreshRequest;
import com.nguyenductien.backend.entity.RefreshToken;
import com.nguyenductien.backend.entity.Role;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.enums.RoleName;
import com.nguyenductien.backend.exception.BadRequestException;
import com.nguyenductien.backend.exception.UnauthorizedException;
import com.nguyenductien.backend.mapper.UserMapper;
import com.nguyenductien.backend.repository.RoleRepository;
import com.nguyenductien.backend.repository.UserRepository;
import com.nguyenductien.backend.security.JwtService;
import com.nguyenductien.backend.service.AuthService;
import com.nguyenductien.backend.service.RefreshTokenService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {

    private final AuthenticationManager authenticationManager;
    private final UserRepository userRepository;
    private final RoleRepository roleRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final RefreshTokenService refreshTokenService;

    @Override
    @Transactional
    public AuthResponse register(RegisterRequest request, String ipAddress, String deviceInfo) {
        if (userRepository.existsByEmailIgnoreCase(request.email())) {
            throw new BadRequestException("Email is already in use");
        }

        Role defaultRole = roleRepository.findByName(RoleName.ROLE_USER)
                .orElseThrow(() -> new BadRequestException("Default user role is not configured"));

        User user = User.builder()
                .fullName(request.fullName().trim())
                .email(request.email().trim().toLowerCase())
                .password(passwordEncoder.encode(request.password()))
                .enabled(true)
                .roles(Set.of(defaultRole))
                .build();

        User savedUser = userRepository.save(user);
        RefreshToken refreshToken = refreshTokenService.createRefreshToken(savedUser, deviceInfo, ipAddress);
        return buildAuthResponse(savedUser, refreshToken);
    }

    @Override
    @Transactional
    public AuthResponse login(LoginRequest request, String ipAddress, String deviceInfo) {
        authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.email().trim().toLowerCase(), request.password())
        );

        User user = userRepository.findByEmailIgnoreCase(request.email().trim().toLowerCase())
                .orElseThrow(() -> new UnauthorizedException("Invalid credentials"));

        RefreshToken refreshToken = refreshTokenService.createRefreshToken(user, deviceInfo, ipAddress);
        return buildAuthResponse(user, refreshToken);
    }

    @Override
    @Transactional
    public AuthResponse refresh(TokenRefreshRequest request, String ipAddress, String deviceInfo) {
        RefreshToken currentToken = refreshTokenService.verifyActiveToken(request.refreshToken());
        User user = currentToken.getUser();

        if (!jwtService.isTokenValid(currentToken.getToken(), user)) {
            refreshTokenService.revokeToken(currentToken.getToken());
            throw new UnauthorizedException("Refresh token is invalid or expired");
        }

        refreshTokenService.revokeToken(currentToken.getToken());
        RefreshToken newRefreshToken = refreshTokenService.createRefreshToken(user, deviceInfo, ipAddress);
        return buildAuthResponse(user, newRefreshToken);
    }

    @Override
    @Transactional
    public void logout(String refreshToken) {
        refreshTokenService.revokeToken(refreshToken);
    }

    private AuthResponse buildAuthResponse(User user, RefreshToken refreshToken) {
        return new AuthResponse(
                jwtService.generateAccessToken(user),
                jwtService.getAccessTokenExpiration(),
                refreshToken.getToken(),
                jwtService.getRefreshTokenExpiration(),
                UserMapper.toResponse(user)
        );
    }
}
