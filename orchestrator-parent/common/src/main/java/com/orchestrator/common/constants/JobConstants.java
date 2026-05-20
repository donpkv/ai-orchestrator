package com.orchestrator.common.constants;

public final class JobConstants {

    private JobConstants() {}

    // Shard identifiers
    public static final String SHARD_A = "shard-a";
    public static final String SHARD_B = "shard-b";

    // Job status values
    public static final String STATUS_PENDING = "PENDING";
    /** Job routed by worker (embedding / cache / LLM); occurs after {@link #STATUS_PENDING}. */
    public static final String STATUS_ROUTED = "ROUTED";
    public static final String STATUS_RUNNING = "RUNNING";
    public static final String STATUS_COMPLETED = "COMPLETED";
    public static final String STATUS_FAILED = "FAILED";
    public static final String STATUS_FAILED_PERMANENT = "FAILED_PERMANENT";

    // Kafka topic names
    public static final String TOPIC_JOB_SUBMITTED = "job-submitted";
    public static final String TOPIC_JOB_ROUTED = "job-routed";
    public static final String TOPIC_JOB_COMPLETED = "job-completed";

    // Cache key prefix
    public static final String CACHE_JOB_PREFIX = "job:";
    public static final String CACHE_STATUS_SUFFIX = ":status";
    /** Redis key prefix for job status cache-aside entries ({@code prefix + jobId}). */
    public static final String CACHE_STATUS_PREFIX = "job:status:";
}
