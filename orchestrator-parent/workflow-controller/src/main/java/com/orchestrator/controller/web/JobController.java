package com.orchestrator.controller.web;

import com.orchestrator.common.dto.JobRequest;
import com.orchestrator.common.dto.JobResponse;
import com.orchestrator.controller.service.JobServicePort;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/jobs")
@Validated
public class JobController {

    private final JobServicePort jobService;

    public JobController(JobServicePort jobService) {
        this.jobService = jobService;
    }

    @PostMapping
    public ResponseEntity<JobResponse> createJob(@Valid @RequestBody JobRequest request) {
        JobResponse body = jobService.submitJob(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(body);
    }

    @GetMapping("/{id}")
    public ResponseEntity<JobResponse> getJob(@PathVariable UUID id) {
        return ResponseEntity.ok(jobService.getJob(id));
    }

    @GetMapping
    public ResponseEntity<List<JobResponse>> getAllJobs() {
        return ResponseEntity.ok(jobService.getAllJobs());
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<Void> updateJobStatus(
            @PathVariable UUID id, @Valid @RequestBody JobStatusUpdateRequest body) {
        jobService.updateJobStatus(id, body.status());
        return ResponseEntity.noContent().build();
    }

    @PatchMapping("/{id}/routing")
    public ResponseEntity<Void> updateJobRouting(
            @PathVariable UUID id, @Valid @RequestBody JobRoutingUpdateRequest body) {
        jobService.updateJobRouting(id, body.workerType(), body.routingDecision());
        return ResponseEntity.noContent().build();
    }
}
