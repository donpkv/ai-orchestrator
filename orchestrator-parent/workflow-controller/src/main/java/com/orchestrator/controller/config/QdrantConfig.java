package com.orchestrator.controller.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class QdrantConfig {

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
}
