# Orchestrator parent

Multi-module Maven project for a local AI orchestrator stack: a gateway, a workflow API service, a background worker, and a shared library.

## Module structure

| Module | Role |
|--------|------|
| **common** | Shared DTOs (for example `JobRequest`, `JobResponse`) and utilities. Plain library JAR; not runnable. |
| **api-gateway** | Spring Cloud Gateway on port **8080**. External HTTP traffic enters here. |
| **workflow-controller** | Spring Boot web service on port **8081**. REST workflow API, JPA persistence, Redis, Kafka producer/consumer hooks as you add them. |
| **job-worker** | Spring Boot worker on port **8082**. Consumes Kafka with group id `job-worker-group`, uses JPA and PostgreSQL alongside shared types from **common**. |

## How the pieces connect

1. **Clients → api-gateway**: HTTP calls hit the gateway at `http://<gateway-host>:8080`.
2. **api-gateway → workflow-controller**: Routes matching `/api/v1/**` are forwarded to `http://workflow-controller-svc:8081` (Kubernetes-style service DNS). Replace `workflow-controller-svc` with `localhost` when running the controller on your machine without that hostname.
3. **workflow-controller ↔ infrastructure**: Reads **PostgreSQL** credentials from `DB_URL`, `DB_USER`, and `DB_PASSWORD`. **Redis** host and port are declared under `spring.redis` as requested; Spring Boot 3 reads connections from `spring.data.redis`, so those values are wired through `${spring.redis.host}` / `${spring.redis.port}`. Kafka bootstrap servers are `kafka-svc:9092`.
4. **job-worker ↔ infrastructure**: Same PostgreSQL env vars; Kafka consumers connect to `kafka-svc:9092` with group id `job-worker-group`.
5. **common**: Linked as a Maven dependency from **api-gateway**, **workflow-controller**, and **job-worker** so all services share the same request/response models.

Actuator is enabled on **api-gateway** and **workflow-controller** with **health** and **info** exposed under the management web endpoints.

## Build

From the `orchestrator-parent` directory:

```bash
mvn clean install
```

This builds **common** first, then the runnable modules, and installs artifacts to your local Maven repository for reuse.

## Configuration notes

- Set `DB_URL`, `DB_USER`, and `DB_PASSWORD` for **workflow-controller** and **job-worker** before starting them, or Spring will fail when binding the datasource.
- Hostnames `workflow-controller-svc`, `redis-svc`, and `kafka-svc` match typical in-cluster service names; adjust `application.yml` or use profiles/overrides for local development.
