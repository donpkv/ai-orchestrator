package com.orchestrator.controller.messaging;

import com.orchestrator.common.constants.JobConstants;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Component;

import java.util.UUID;
import java.util.concurrent.CompletableFuture;

@Component
public class JobEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(JobEventPublisher.class);

    private final KafkaTemplate<String, String> kafkaTemplate;

    public JobEventPublisher(KafkaTemplate<String, String> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void publishJobSubmitted(UUID jobId, String description, int priority, String shardKey) {
        try {
            String json =
                    "{\"jobId\":\""
                            + jobId
                            + "\",\"description\":\""
                            + escapeJson(description)
                            + "\",\"priority\":"
                            + priority
                            + ",\"shardKey\":\""
                            + escapeJson(shardKey)
                            + "\"}";
            CompletableFuture<SendResult<String, String>> future =
                    kafkaTemplate.send(JobConstants.TOPIC_JOB_SUBMITTED, jobId.toString(), json);
            future.whenComplete(
                    (result, throwable) -> {
                        if (throwable != null) {
                            log.warn("Kafka publish failed for job {}: {}", jobId, throwable.getMessage(), throwable);
                        } else {
                            log.info("Kafka publish succeeded for job {}", jobId);
                        }
                    });
        } catch (Exception e) {
            log.warn("Kafka publish failed for job {}: {}", jobId, e.getMessage(), e);
        }
    }

    private static String escapeJson(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
