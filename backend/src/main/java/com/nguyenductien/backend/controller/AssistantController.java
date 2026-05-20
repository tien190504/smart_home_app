package com.nguyenductien.backend.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.nguyenductien.backend.dto.assistant.AssistantChatRequest;
import com.nguyenductien.backend.dto.assistant.AssistantChatResponse;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.service.AssistantService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@Validated
@RestController
@RequestMapping("/api/assistant")
@RequiredArgsConstructor
public class AssistantController {

    private final AssistantService assistantService;

    @PostMapping("/chat")
    public ResponseEntity<AssistantChatResponse> chat(
            @Valid @RequestBody AssistantChatRequest request,
            @AuthenticationPrincipal User currentUser
    ) {
        return ResponseEntity.ok(assistantService.chat(request, currentUser));
    }
}
