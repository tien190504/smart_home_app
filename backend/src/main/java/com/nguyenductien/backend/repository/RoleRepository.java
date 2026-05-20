package com.nguyenductien.backend.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.nguyenductien.backend.entity.Role;
import com.nguyenductien.backend.enums.RoleName;

public interface RoleRepository extends JpaRepository<Role, Long> {

    Optional<Role> findByName(RoleName name);

    List<Role> findAllByOrderByNameAsc();
}
