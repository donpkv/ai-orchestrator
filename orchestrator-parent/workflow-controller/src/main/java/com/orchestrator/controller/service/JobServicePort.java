package com.orchestrator.controller.service;

import com.orchestrator.common.dto.JobRequest;
import com.orchestrator.common.dto.JobResponse;

import java.util.List;
import java.util.UUID;

/**
 * Port interface for job operations (Hexagonal Architecture).
 * JobService implements this. Tests can mock it without touching the real implementation.
 * Future: a different routing strategy (consistent hashing, range-based) just implements this port.
 */
public interface JobServicePort {

    JobResponse submitJob(JobRequest request);

    JobResponse getJob(UUID id);

    List<JobResponse> getAllJobs();

    void updateJobStatus(UUID id, String newStatus);

    void updateJobRouting(UUID id, String workerType, String routingDecision);
}
