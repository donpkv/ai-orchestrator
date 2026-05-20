package com.orchestrator.worker.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Service
public class OllamaService {

    private static final Logger log = LoggerFactory.getLogger(OllamaService.class);

    private static final Pattern JSON_OBJECT =
            Pattern.compile("\\{.*\\}", Pattern.DOTALL);

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final String ollamaBaseUrl;

    public OllamaService(
            @Qualifier("ollamaRestTemplate") RestTemplate restTemplate,
            ObjectMapper objectMapper,
            @Value("${ollama.base-url:http://ollama-svc:11434}") String ollamaBaseUrl) {
        this.restTemplate = restTemplate;
        this.objectMapper = objectMapper;
        this.ollamaBaseUrl = normalizeBaseUrl(ollamaBaseUrl);
    }

    public RoutingDecision route(String jobDescription) {
        String prompt =
                "You are a job routing system. Analyze this job and respond ONLY with valid JSON, no explanation, no markdown.\n"
                        + "Job: "
                        + jobDescription
                        + "\n"
                        + "Respond with exactly this JSON structure:\n"
                        + "{\"workerType\": \"<one of: data-processing, notification, deployment, analysis, general>\",\n"
                        + "\"estimatedSeconds\": <integer between 1 and 300>,\n"
                        + "\"suggestedPriority\": <integer between 1 and 10>,\n"
                        + "\"reasoning\": \"<one sentence max>\"}";

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("model", "mistral:7b");
        body.put("prompt", prompt);
        body.put("stream", false);

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);

            String url = ollamaBaseUrl + "/api/generate";
            String raw = restTemplate.postForEntity(url, entity, String.class).getBody();
            if (raw == null || raw.isBlank()) {
                log.warn("Ollama routing: empty response body");
                return RoutingDecision.defaultDecision();
            }
            JsonNode root = objectMapper.readTree(raw);
            String responseText = root.path("response").asText("");
            RoutingDecision parsed = parseRoutingJson(responseText);
            if (parsed == null) {
                log.warn("Ollama routing: could not parse model output: {}", truncate(responseText, 400));
                return RoutingDecision.defaultDecision();
            }
            return parsed;
        } catch (Exception e) {
            log.warn("Ollama routing failed: {}", e.getMessage());
            return RoutingDecision.defaultDecision();
        }
    }

    private RoutingDecision parseRoutingJson(String responseText) {
        if (responseText == null || responseText.isBlank()) {
            return null;
        }
        String jsonSlice = extractJsonObject(responseText);
        if (jsonSlice == null) {
            return null;
        }
        try {
            return objectMapper.readValue(jsonSlice, RoutingDecision.class);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String extractJsonObject(String responseText) {
        int start = responseText.indexOf('{');
        int end = responseText.lastIndexOf('}');
        if (start >= 0 && end > start) {
            return responseText.substring(start, end + 1);
        }
        Matcher m = JSON_OBJECT.matcher(responseText);
        if (m.find()) {
            return m.group();
        }
        return null;
    }

    private static String truncate(String s, int maxLen) {
        if (s == null) {
            return null;
        }
        if (s.length() <= maxLen) {
            return s;
        }
        return s.substring(0, maxLen) + "...";
    }

    private static String normalizeBaseUrl(String ollamaBaseUrl) {
        if (ollamaBaseUrl == null || ollamaBaseUrl.isEmpty()) {
            return "http://ollama-svc:11434";
        }
        return ollamaBaseUrl.endsWith("/")
                ? ollamaBaseUrl.substring(0, ollamaBaseUrl.length() - 1)
                : ollamaBaseUrl;
    }
}
