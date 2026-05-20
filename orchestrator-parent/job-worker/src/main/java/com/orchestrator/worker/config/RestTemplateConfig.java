package com.orchestrator.worker.config;

import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class RestTemplateConfig {

    @Bean
    @Primary
    public RestTemplate restTemplate() {
        // HttpComponentsClientHttpRequestFactory (Apache HttpClient) supports PATCH,
        // unlike the default SimpleClientHttpRequestFactory (Java HttpURLConnection).
        return new RestTemplate(new HttpComponentsClientHttpRequestFactory(HttpClients.createDefault()));
    }
}
