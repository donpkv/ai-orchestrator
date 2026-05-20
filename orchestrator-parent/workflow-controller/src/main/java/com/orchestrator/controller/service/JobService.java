package com.orchestrator.controller.service;

import com.orchestrator.common.constants.JobConstants;
import com.orchestrator.common.dto.JobRequest;
import com.orchestrator.common.dto.JobResponse;
import com.orchestrator.controller.config.ShardContextHolder;
import com.orchestrator.controller.model.Job;
import com.orchestrator.controller.messaging.JobEventPublisher;
import com.orchestrator.controller.repository.JobRepository;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Service
public class JobService implements JobServicePort {

    private final JobRepository jobRepository;
    private final RedisTemplate<String, String> redisTemplate;
    private final JobEventPublisher jobEventPublisher;

    public JobService(
            JobRepository jobRepository,
            @Qualifier("workflowRedisTemplate") RedisTemplate<String, String> redisTemplate,
            JobEventPublisher jobEventPublisher) {
        this.jobRepository = jobRepository;
        this.redisTemplate = redisTemplate;
        this.jobEventPublisher = jobEventPublisher;
    }

    public JobResponse submitJob(JobRequest request) {
        UUID id = UUID.randomUUID();
        int shardKey = shardOf(id);
        try {
            ShardContextHolder.setShard(shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B);
            Job job = Job.builder()
                    .id(id)
                    .description(request.description())
                    .priority(request.priority())
                    .shardKey(shardKey)
                    .build();

            job = jobRepository.save(job);

            cachePutStatus(job.getId(), job.getStatus());
            jobEventPublisher.publishJobSubmitted(
                    job.getId(),
                    job.getDescription(),
                    job.getPriority(),
                    shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B);

            return new JobResponse(
                    job.getId(),
                    job.getDescription(),
                    job.getPriority(),
                    job.getStatus(),
                    shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B,
                    job.getWorkerType(),
                    job.getSubmittedAt());
        } finally {
            ShardContextHolder.clear();
        }
    }

    public JobResponse getJob(UUID id) {
        String cached = cacheGetStatus(id);
        int shardKey = shardOf(id);
        try {
            ShardContextHolder.setShard(shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B);
            Job job = jobRepository.findById(id)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
            if (cached != null) {
                return new JobResponse(
                        job.getId(),
                        job.getDescription(),
                        job.getPriority(),
                        cached,
                        shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B,
                        job.getWorkerType(),
                        job.getSubmittedAt());
            }
            cachePutStatus(id, job.getStatus());
            return toJobResponse(job);
        } finally {
            ShardContextHolder.clear();
        }
    }

    public List<JobResponse> getAllJobs() {
        List<JobResponse> merged = new ArrayList<>();
        try {
            ShardContextHolder.setShard(JobConstants.SHARD_A);
            merged.addAll(jobRepository.findAll().stream().map(this::toJobResponse).toList());
        } finally {
            ShardContextHolder.clear();
        }
        try {
            ShardContextHolder.setShard(JobConstants.SHARD_B);
            merged.addAll(jobRepository.findAll().stream().map(this::toJobResponse).toList());
        } finally {
            ShardContextHolder.clear();
        }
        merged.sort((a, b) -> b.submittedAt().compareTo(a.submittedAt()));
        return merged;
    }

    public void updateJobStatus(UUID id, String newStatus) {
        int shardKey = shardOf(id);
        try {
            ShardContextHolder.setShard(shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B);
            Job job = jobRepository.findById(id)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
            job.setStatus(newStatus);
            jobRepository.save(job);
            cachePutStatus(id, newStatus);
        } finally {
            ShardContextHolder.clear();
        }
    }

    public void updateJobRouting(UUID id, String workerType, String routingDecision) {
        int shardKey = shardOf(id);
        try {
            ShardContextHolder.setShard(shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B);
            Job job = jobRepository.findById(id)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
            job.setWorkerType(workerType);
            job.setRoutingDecision(routingDecision);
            job.setStatus(JobConstants.STATUS_ROUTED);
            jobRepository.save(job);
            cachePutStatus(id, JobConstants.STATUS_ROUTED);
        } finally {
            ShardContextHolder.clear();
        }
    }

    private static int shardOf(UUID id) {
        return Math.floorMod(id.hashCode(), 2);
    }

    private JobResponse toJobResponse(Job job) {
        int shardKey = job.getShardKey();
        return new JobResponse(
                job.getId(),
                job.getDescription(),
                job.getPriority(),
                job.getStatus(),
                shardKey == 0 ? JobConstants.SHARD_A : JobConstants.SHARD_B,
                job.getWorkerType(),
                job.getSubmittedAt());
    }

    private void cachePutStatus(UUID id, String status) {
        try {
            redisTemplate
                    .opsForValue()
                    .set(JobConstants.CACHE_STATUS_PREFIX + id, status, 5, TimeUnit.MINUTES);
        } catch (Exception ignored) {
            // Ignore Redis errors; PostgreSQL remains authoritative.
        }
    }

    private String cacheGetStatus(UUID id) {
        try {
            return redisTemplate.opsForValue().get(JobConstants.CACHE_STATUS_PREFIX + id);
        } catch (Exception e) {
            return null;
        }
    }
}
