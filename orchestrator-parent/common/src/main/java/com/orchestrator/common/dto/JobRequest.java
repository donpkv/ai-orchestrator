package com.orchestrator.common.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

public record JobRequest(
        @NotBlank String description,
        @Min(1) @Max(10) int priority
) {
    public JobRequest(String description) {
        this(description, 5);
    }
}
