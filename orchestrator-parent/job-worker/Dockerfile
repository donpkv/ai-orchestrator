FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build

COPY pom.xml ./
COPY .mvn/ ./.mvn/
COPY common/ ./common/
COPY api-gateway/ ./api-gateway/
COPY workflow-controller/ ./workflow-controller/
COPY job-worker/ ./job-worker/

RUN apk add --no-cache maven \
    && mvn -s .mvn/settings.xml -pl job-worker -am clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app

COPY --from=builder /build/job-worker/target/job-worker-*.jar app.jar
RUN chown appuser:appgroup app.jar

USER appuser
EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8082/actuator/health || exit 1

ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
