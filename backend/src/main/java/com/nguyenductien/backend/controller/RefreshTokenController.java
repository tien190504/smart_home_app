package com.nguyenductien.backend.controller;

import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.nguyenductien.backend.dto.auth.SessionResponse;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.service.RefreshTokenService;

import lombok.RequiredArgsConstructor;

@RestController
@RequestMapping("/api/sessions")
@RequiredArgsConstructor
public class RefreshTokenController {

    private final RefreshTokenService refreshTokenService;

    @GetMapping
    public ResponseEntity<List<SessionResponse>> getActiveSessions(@AuthenticationPrincipal User currentUser) {
        return ResponseEntity.ok(refreshTokenService.getActiveSessions(currentUser));
    }

    @DeleteMapping("/{sessionId}")
    public ResponseEntity<Map<String, String>> revokeSession(
            @PathVariable Long sessionId,
            @AuthenticationPrincipal User currentUser
    ) {
        refreshTokenService.revokeSession(sessionId, currentUser);
        return ResponseEntity.ok(Map.of("message", "Session revoked successfully"));
    }

    @DeleteMapping
    public ResponseEntity<Map<String, String>> revokeAllSessions(@AuthenticationPrincipal User currentUser) {
        refreshTokenService.revokeAllSessions(currentUser);
        return ResponseEntity.ok(Map.of("message", "All sessions revoked successfully"));
    }
}
