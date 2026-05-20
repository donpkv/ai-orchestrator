package com.orchestrator.controller.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "jobs")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Job {

    @Id
    private UUID id;

    private String description;

    private int priority;

    private String status;

    @Column(name = "shard_key")
    private int shardKey;

    @Column(name = "worker_type")
    private String workerType;

    @Column(name = "routing_decision")
    private String routingDecision;

    @Column(name = "submitted_at")
    private Instant submittedAt;

    @Column(name = "updated_at")
    private Instant updatedAt;

    @PrePersist
    void onCreate() {
        Instant now = Instant.now();
        submittedAt = now;
        updatedAt = now;
        status = "PENDING";
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }
}
