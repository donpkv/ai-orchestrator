package com.orchestrator.controller.ai;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record RoutingDecision(
        String workerType,
        int estimatedSeconds,
        int suggestedPriority,
        String reasoning
) {

    public static RoutingDecision defaultDecision() {
        return new RoutingDecision("general", 30, 5, "default routing");
    }

    public String toJson() {
        return "{\"workerType\":\"" + escapeJson(workerType)
                + "\",\"estimatedSeconds\":" + estimatedSeconds
                + ",\"suggestedPriority\":" + suggestedPriority
                + ",\"reasoning\":\"" + escapeJson(reasoning) + "\"}";
    }

    private static String escapeJson(String raw) {
        if (raw == null) {
            return "";
        }
        return raw.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
