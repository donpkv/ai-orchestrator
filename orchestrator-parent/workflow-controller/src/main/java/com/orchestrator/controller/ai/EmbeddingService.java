package com.orchestrator.controller.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Service
public class EmbeddingService {

    private static final Logger log = LoggerFactory.getLogger(EmbeddingService.class);

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final String ollamaBaseUrl;

    public EmbeddingService(
            RestTemplate restTemplate,
            ObjectMapper objectMapper,
            @Value("${ollama.base-url:http://ollama-svc:11434}") String ollamaBaseUrl) {
        this.restTemplate = restTemplate;
        this.objectMapper = objectMapper;
        this.ollamaBaseUrl = ollamaBaseUrl.endsWith("/")
                ? ollamaBaseUrl.substring(0, ollamaBaseUrl.length() - 1)
                : ollamaBaseUrl;
    }

    public float[] embed(String text) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            Map<String, Object> body = new HashMap<>();
            body.put("model", "nomic-embed-text");
            body.put("input", text);

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String response = restTemplate.postForObject(ollamaBaseUrl + "/api/embed", entity, String.class);
            if (response == null) {
                log.warn("Ollama embed returned empty response");
                return null;
            }

            JsonNode root = objectMapper.readTree(response);
            JsonNode embeddings = root.path("embeddings");
            if (!embeddings.isArray() || embeddings.isEmpty()) {
                log.warn("Ollama embed response missing embeddings array: {}", response);
                return null;
            }
            JsonNode first = embeddings.path(0);
            if (!first.isArray() || first.isEmpty()) {
                log.warn("Ollama embed response missing first embedding vector: {}", response);
                return null;
            }

            float[] out = new float[first.size()];
            int i = 0;
            for (JsonNode n : first) {
                out[i++] = (float) n.asDouble();
            }
            return out;
        } catch (Exception e) {
            log.warn("Failed to embed text via Ollama: {}", e.getMessage());
            return null;
        }
    }
}
