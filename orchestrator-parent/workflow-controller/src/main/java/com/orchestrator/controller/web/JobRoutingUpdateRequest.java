package com.orchestrator.controller.web;

import jakarta.validation.constraints.NotBlank;

public record JobRoutingUpdateRequest(@NotBlank String workerType, String routingDecision) {}
