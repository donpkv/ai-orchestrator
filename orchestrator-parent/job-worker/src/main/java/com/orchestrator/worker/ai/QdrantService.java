package com.orchestrator.worker.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Service
public class QdrantService {

    private static final Logger log = LoggerFactory.getLogger(QdrantService.class);
    private static final float SIMILARITY_THRESHOLD = 0.9f;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final String qdrantBaseUrl;
    private final String collectionName;

    public QdrantService(
            RestTemplate restTemplate,
            ObjectMapper objectMapper,
            @Qualifier("qdrantBaseUrl") String qdrantBaseUrl,
            @Qualifier("qdrantCollectionName") String collectionName) {
        this.restTemplate = restTemplate;
        this.objectMapper = objectMapper;
        this.qdrantBaseUrl = qdrantBaseUrl;
        this.collectionName = collectionName;
    }

    public Optional<String> findSimilarRouting(float[] embedding) {
        if (embedding == null || embedding.length == 0) {
            return Optional.empty();
        }
        try {
            String url = qdrantBaseUrl + "/collections/" + collectionName + "/points/search";

            Map<String, Object> body = new HashMap<>();
            body.put("vector", floatArrayToList(embedding));
            body.put("limit", 1);
            body.put("with_payload", true);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

            String response = restTemplate.postForObject(url, request, String.class);
            if (response == null) return Optional.empty();

            JsonNode root = objectMapper.readTree(response);
            JsonNode results = root.path("result");
            if (!results.isArray() || results.isEmpty()) return Optional.empty();

            JsonNode top = results.get(0);
            float score = (float) top.path("score").asDouble(0.0);
            if (score < SIMILARITY_THRESHOLD) return Optional.empty();

            String routing = top.path("payload").path("routingDecision").asText(null);
            if (routing == null || routing.isBlank()) return Optional.empty();

            log.info("Qdrant cache hit (score={}) for routing: {}", score, routing);
            return Optional.of(routing);
        } catch (Exception e) {
            log.debug("Qdrant similarity search failed: {}", e.getMessage());
            return Optional.empty();
        }
    }

    public void storeJobEmbedding(UUID jobId, float[] embedding, String routingDecision) {
        if (jobId == null || embedding == null || embedding.length == 0 || routingDecision == null) {
            return;
        }
        try {
            ensureCollectionExists(embedding.length);

            String url = qdrantBaseUrl + "/collections/" + collectionName + "/points";

            Map<String, Object> payload = new HashMap<>();
            payload.put("routingDecision", routingDecision);
            payload.put("jobId", jobId.toString());

            Map<String, Object> point = new HashMap<>();
            point.put("id", jobId.toString());
            point.put("vector", floatArrayToList(embedding));
            point.put("payload", payload);

            Map<String, Object> body = new HashMap<>();
            body.put("points", List.of(point));

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

            restTemplate.put(url, request);
            log.info("Stored embedding for job {} in Qdrant collection '{}'", jobId, collectionName);
        } catch (Exception e) {
            log.warn("Failed to upsert job embedding to Qdrant: {}", e.getMessage());
        }
    }

    private void ensureCollectionExists(int vectorSize) {
        try {
            String checkUrl = qdrantBaseUrl + "/collections/" + collectionName;
            restTemplate.getForObject(checkUrl, String.class);
        } catch (Exception e) {
            // Collection doesn't exist — create it
            try {
                String createUrl = qdrantBaseUrl + "/collections/" + collectionName;
                Map<String, Object> vectorsConfig = new HashMap<>();
                vectorsConfig.put("size", vectorSize);
                vectorsConfig.put("distance", "Cosine");

                Map<String, Object> body = new HashMap<>();
                body.put("vectors", vectorsConfig);

                HttpHeaders headers = new HttpHeaders();
                headers.setContentType(MediaType.APPLICATION_JSON);
                HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

                restTemplate.put(createUrl, request);
                log.info("Created Qdrant collection '{}' with size={} distance=Cosine",
                        collectionName, vectorSize);
            } catch (Exception ce) {
                log.warn("Failed to create Qdrant collection '{}': {}", collectionName, ce.getMessage());
            }
        }
    }

    private List<Float> floatArrayToList(float[] arr) {
        List<Float> out = new ArrayList<>(arr.length);
        for (float v : arr) {
            out.add(v);
        }
        return out;
    }
}
