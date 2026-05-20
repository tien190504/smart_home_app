package com.nguyenductien.backend.service;

import java.util.List;

import com.nguyenductien.backend.dto.automation.AutomationScheduleRequest;
import com.nguyenductien.backend.dto.automation.AutomationScheduleResponse;
import com.nguyenductien.backend.entity.User;

public interface AutomationScheduleService {

    List<AutomationScheduleResponse> getSchedules(User currentUser);

    AutomationScheduleResponse createSchedule(AutomationScheduleRequest request, User currentUser);

    AutomationScheduleResponse updateSchedule(Long scheduleId, AutomationScheduleRequest request, User currentUser);

    void deleteSchedule(Long scheduleId, User currentUser);
}
