package com.orchestrator.controller.repository;

import com.orchestrator.controller.model.Job;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface JobRepository extends JpaRepository<Job, UUID> {

    List<Job> findByStatus(String status);
}
