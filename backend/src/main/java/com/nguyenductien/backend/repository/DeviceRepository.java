package com.nguyenductien.backend.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.nguyenductien.backend.entity.Device;

public interface DeviceRepository extends JpaRepository<Device, Long> {

    boolean existsByDeviceCodeIgnoreCase(String deviceCode);

    Optional<Device> findByDeviceCodeIgnoreCase(String deviceCode);

    List<Device> findAllByOwnerIdOrderByCreatedAtDesc(Long ownerId);
}
