package com.orchestrator.worker.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class AiConfig {

    @Bean(name = "ollamaRestTemplate")
    public RestTemplate ollamaRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(30_000);
        return new RestTemplate(factory);
    }

    @Bean(name = "qdrantBaseUrl")
    public String qdrantBaseUrl(
            @Value("${qdrant.host:qdrant-svc}") String host,
            @Value("${qdrant.port:6333}") int port) {
        return "http://" + host + ":" + port;
    }

    @Bean(name = "qdrantCollectionName")
    public String qdrantCollectionName() {
        return "job-embeddings";
    }

    @Bean
    public ObjectMapper objectMapper() {
        return new ObjectMapper();
    }
}
