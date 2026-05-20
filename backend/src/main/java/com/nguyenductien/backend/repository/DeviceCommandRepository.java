package com.nguyenductien.backend.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

import com.nguyenductien.backend.entity.DeviceCommand;

public interface DeviceCommandRepository extends JpaRepository<DeviceCommand, Long> {

    List<DeviceCommand> findTop50ByDeviceIdOrderByRequestedAtDesc(Long deviceId);
}
