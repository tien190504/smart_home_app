package com.nguyenductien.backend.service;

import com.nguyenductien.backend.dto.assistant.AssistantChatRequest;
import com.nguyenductien.backend.dto.assistant.AssistantChatResponse;
import com.nguyenductien.backend.entity.User;

public interface AssistantService {

    AssistantChatResponse chat(AssistantChatRequest request, User currentUser);
}
