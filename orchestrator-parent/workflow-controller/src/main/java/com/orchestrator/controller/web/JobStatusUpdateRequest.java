package com.orchestrator.controller.web;

import jakarta.validation.constraints.NotBlank;

public record JobStatusUpdateRequest(@NotBlank String status) {
}
