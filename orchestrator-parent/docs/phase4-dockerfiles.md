# Phase 4: Multi-stage Dockerfiles

## What is a multi-stage build, and why use it?

A **multi-stage** Dockerfile uses more than one `FROM` image. The first stage (the **builder**) installs the JDK and Maven, copies the source, and runs `mvn package` to produce a JAR. Later stages do not inherit that bulky layer stack: the final image only copies the artifact (for example `app.jar`) from the builder.

That matters because a typical builder image is large (JDK plus Maven tooling is often on the order of hundreds of megabytes), while the **runtime** image only needs a JRE and your JAR. Smaller images mean faster deploys, less registry storage, and a smaller attack surface. In rough terms: builder can be around **~500MB** depending on the base image, while a JRE-only runtime is often closer to **~100MB**.

## Why `eclipse-temurin:21-jre-alpine`?

[Eclipse Temurin](https://adoptium.net/) provides well-maintained OpenJDK builds. The **`21-jre`** tag ships the Java runtime only (no compiler or full JDK), which is what you need to run a Spring Boot fat JAR.

**Alpine** Linux uses **musl** and a minimal userspace; the base filesystem is small (on the order of a few megabytes for the distro pieces you actually use). Combining Temurin with **`-alpine`** yields one of the smaller practical choices for running Java 21 in production, as long as your stack is compatible with Alpine (glibc vs musl is the main caveat).

## `-XX:+UseContainerSupport`

This JVM option (enabled by default on modern HotSpot builds, but set explicitly here for clarity) makes the JVM **respect Linux cgroup limits** that apply to the container (CPU and memory), instead of assuming it can use all memory or CPUs of the host machine.

When the process runs in Kubernetes, Docker, or other runtimes that set cgroup memory and CPU quotas, **container-aware** behavior avoids over-allocating heap and reduces out-of-memory kills on the node.

## `-XX:MaxRAMPercentage=75.0`

This sets the **maximum heap size** as a fraction of the memory the JVM believes is available **for the container** (after container awareness). So if the pod has a memory limit, the JVM caps the heap at **75%** of that limit (with the remainder left for metaspace, thread stacks, native code, and direct buffers).

Tuning this percentage is a trade-off: higher values use more heap for caching and throughput; lower values leave more headroom for off-heap usage and reduce risk of hitting the cgroup limit.

## Why build from `orchestrator-parent`?

These services are **Maven multimodule** projects. The root `pom.xml` is the **parent** POM: it declares modules (`common`, `api-gateway`, etc.) and shared dependency management. Module POMs use `<relativePath>../pom.xml</relativePath>` (or similar) to resolve the parent.

`docker build` sends a **build context** directory to the daemon. All `COPY` paths are relative to that context. If the context were only `api-gateway/`, the Docker build would not see the parent `pom.xml` or sibling `common/`, and Maven would fail. Building with **context = `orchestrator-parent`** (and `-f api-gateway/Dockerfile`, etc.) keeps the parent POM, `.mvn` settings, `common`, and the target module in one tree so `mvn -pl <module> -am` can resolve the reactor correctly.

---

## Image build helper

`scripts/build-images.ps1` (located in the root `scripts/` folder alongside all other project scripts) sets `DOCKER_BUILDKIT=1`, builds each image from the `orchestrator-parent` directory, loads images into Minikube, and lists `local-ai/*` image sizes.

---

## Security hardening applied (post-review)

### Non-root user (HIGH)
All three runtime images now create a dedicated system user (`appuser`) and group (`appgroup`) and switch to that user before the `ENTRYPOINT`. Running as non-root limits privilege escalation risk if an attacker exploits the Java application.

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
...
RUN chown appuser:appgroup app.jar
USER appuser
```

### HEALTHCHECK
Each Dockerfile now includes a Docker-native health check that polls `/actuator/health` every 30 seconds. `--start-period=60s` gives Spring Boot time to start up before the container is marked unhealthy.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:808X/actuator/health || exit 1
```

### .dockerignore additions
Added `.env`, `.env.*`, `backups/`, and `*.sql` to `.dockerignore` to prevent accidentally leaking credentials or SQL scripts containing secrets into the build context.

### Known accepted risks
| Risk | Severity | Status |
|------|----------|--------|
| Floating base image tags (`21-jre-alpine`) | Medium | Accepted for local dev; pin in prod CI |
| Maven cache not persisted between builds (slow rebuilds) | Low | Accepted; use BuildKit mount cache when moving to CI |
