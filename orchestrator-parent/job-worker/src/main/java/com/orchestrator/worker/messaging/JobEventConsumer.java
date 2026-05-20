package com.orchestrator.worker.messaging;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.orchestrator.worker.ai.EmbeddingService;
import com.orchestrator.worker.ai.OllamaService;
import com.orchestrator.worker.ai.QdrantService;
import com.orchestrator.worker.ai.RoutingDecision;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Component
public class JobEventConsumer {

    private static final Logger log = LoggerFactory.getLogger(JobEventConsumer.class);

    private final ObjectMapper objectMapper;
    private final RestTemplate restTemplate;
    private final EmbeddingService embeddingService;
    private final QdrantService qdrantService;
    private final OllamaService ollamaService;
    private final String workflowControllerBaseUrl;

    public JobEventConsumer(
            ObjectMapper objectMapper,
            RestTemplate restTemplate,
            EmbeddingService embeddingService,
            QdrantService qdrantService,
            OllamaService ollamaService,
            @Value("${workflow.controller.url}") String workflowControllerBaseUrl) {
        this.objectMapper = objectMapper;
        this.restTemplate = restTemplate;
        this.embeddingService = embeddingService;
        this.qdrantService = qdrantService;
        this.ollamaService = ollamaService;
        this.workflowControllerBaseUrl = normalizeBaseUrl(workflowControllerBaseUrl);
    }

    @KafkaListener(
            topics = "job-submitted",
            groupId = "job-worker-group",
            containerFactory = "kafkaListenerContainerFactory")
    public void handleJobSubmitted(String message) {
        UUID jobId = null;
        try {
            JsonNode root = objectMapper.readTree(message);
            String jobIdStr = root.path("jobId").asText(null);
            if (jobIdStr == null || jobIdStr.isBlank()) {
                log.warn("[job-worker] Missing jobId in message: {}", message);
                return;
            }
            jobId = UUID.fromString(jobIdStr);
            String description = root.path("description").asText("");

            log.info("[job-worker] Step embed starting jobId={}", jobId);
            float[] vector = embeddingService.embed(description);

            log.info("[job-worker] Step qdrant lookup jobId={}", jobId);
            Optional<String> cached = qdrantService.findSimilarRouting(vector);

            String workerType;
            String routingDecision;
            if (cached.isPresent()) {
                workerType = cached.get();
                routingDecision =
                        "{\"source\":\"qdrant-cache\",\"workerType\":\""
                                + escapeJson(workerType)
                                + "\"}";
                log.info("[job-worker] Step routing cache HIT jobId={} workerType={}", jobId, workerType);
            } else {
                log.info("[job-worker] Step routing cache MISS jobId={} calling Ollama", jobId);
                RoutingDecision decision = ollamaService.route(description);
                workerType = decision.workerType();
                routingDecision = decision.toJson();
                qdrantService.storeJobEmbedding(jobId, vector, workerType);
            }

            log.info("[job-worker] Step PATCH routing jobId={}", jobId);
            patchJobRouting(jobId, workerType, routingDecision);

            log.info("[job-worker] Step simulated execution jobId={}", jobId);
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Interrupted during simulated work", e);
            }

            patchJobStatus(jobId, "COMPLETED");
            log.info("[job-worker] Job {} marked COMPLETED", jobId);
        } catch (Exception e) {
            log.error("[job-worker] Pipeline failed jobId={}: {}", jobId, e.getMessage(), e);
            if (jobId != null) {
                try {
                    patchJobStatus(jobId, "FAILED");
                    log.warn("[job-worker] Job {} marked FAILED after pipeline error", jobId);
                } catch (Exception ex) {
                    log.warn("[job-worker] Recovery PATCH FAILED failed jobId={}: {}", jobId, ex.getMessage());
                }
            }
        }
    }

    private void patchJobRouting(UUID jobId, String workerType, String routingDecision)
            throws JsonProcessingException {
        String url = workflowControllerBaseUrl + "/api/v1/jobs/" + jobId + "/routing";
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        Map<String, String> body = new LinkedHashMap<>();
        body.put("workerType", workerType);
        body.put("routingDecision", routingDecision);
        String json = objectMapper.writeValueAsString(body);
        HttpEntity<String> entity = new HttpEntity<>(json, headers);
        restTemplate.exchange(url, HttpMethod.PATCH, entity, Void.class);
    }

    private void patchJobStatus(UUID jobId, String status) {
        String url = workflowControllerBaseUrl + "/api/v1/jobs/" + jobId + "/status";
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<String> entity = new HttpEntity<>("{\"status\":\"" + status + "\"}", headers);
        restTemplate.exchange(url, HttpMethod.PATCH, entity, Void.class);
    }

    private static String escapeJson(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private static String normalizeBaseUrl(String url) {
        if (url == null || url.isBlank()) {
            return "http://workflow-controller-svc:8081";
        }
        return url.endsWith("/") ? url.substring(0, url.length() - 1) : url;
    }
}
