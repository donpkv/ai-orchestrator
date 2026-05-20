package com.orchestrator.controller.config;

public final class ShardContextHolder {

    private static final ThreadLocal<String> SHARD = new ThreadLocal<>();

    private ShardContextHolder() {
    }

    public static void setShard(String shard) {
        SHARD.set(shard);
    }

    public static String getShard() {
        return SHARD.get();
    }

    public static void clear() {
        SHARD.remove();
    }
}
