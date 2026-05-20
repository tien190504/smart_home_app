package com.nguyenductien.backend.repository;

import java.util.List;

import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.repository.JpaRepository;

import com.nguyenductien.backend.entity.AutomationSchedule;

public interface AutomationScheduleRepository extends JpaRepository<AutomationSchedule, Long> {

    List<AutomationSchedule> findAllByDeviceOwnerIdOrderByCreatedAtDesc(Long ownerId);

    List<AutomationSchedule> findAllByEnabledTrue(Sort sort);
}
