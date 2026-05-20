package com.orchestrator.common.dto;

import java.time.Instant;
import java.util.UUID;

public record JobResponse(
        UUID id,
        String description,
        int priority,
        String status,
        String shardKey,
        String workerType,
        Instant submittedAt
) {
}
