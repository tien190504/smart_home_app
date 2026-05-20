package com.nguyenductien.backend.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.nguyenductien.backend.entity.TelemetryRecord;

public interface TelemetryRecordRepository extends JpaRepository<TelemetryRecord, Long> {

    List<TelemetryRecord> findTop50ByDeviceIdOrderByRecordedAtDesc(Long deviceId);

    Optional<TelemetryRecord> findFirstByDeviceIdOrderByRecordedAtDesc(Long deviceId);
}
