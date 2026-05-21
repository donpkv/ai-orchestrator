# Troubleshooting Log

Every significant problem encountered during development, its root cause, and the exact fix applied. Ordered chronologically by phase.

---

## Phase 1 — Infrastructure Setup

### TL-01: Minikube OOM — Only 7.9 GB RAM Available
**Symptom:** `minikube start` succeeded but pods OOMKilled. `minikube config view` showed `memory=7942MB`.
**Root cause:** WSL 2 default memory cap is 50% of host RAM. With 16 GB host, WSL got 8 GB, leaving ~7.9 GB for Minikube.
**Fix:** Created `C:\Users\piyushvi\.wslconfig`:
```ini
[wsl2]
memory=20GB
processors=6
swap=4GB
```
Ran `wsl --shutdown` then restarted Docker Desktop. Minikube then received the full 16 GB allocation.

---

### TL-02: `ImagePullBackOff` on Ingress Nginx Pods
**Symptom:** `kubectl get pods -n ingress-nginx` showed `ImagePullBackOff`. Corporate VPN blocked `registry.k8s.io` from inside the Minikube Docker container.
**Root cause:** `minikube addons enable ingress` triggers Minikube to pull the controller image from inside its Docker container, which goes through corporate network inspection. The corporate proxy's self-signed certificate was not trusted inside the container.
**Fix:**
1. Pulled images on Windows host (which trusts corporate CA): `docker pull registry.k8s.io/ingress-nginx/controller:v1.14.3`
2. Loaded into Minikube: `minikube image load registry.k8s.io/ingress-nginx/controller:v1.14.3`
3. Patched deployment to use `imagePullPolicy: IfNotPresent` to avoid digest verification
4. Baked into `setup-cluster.ps1` so all future cluster recreations are self-contained

---

### TL-03: `kubectl patch` JSON Failing in PowerShell
**Symptom:** `kubectl patch ... --patch '{"spec":...}'` failed with JSON parse errors.
**Root cause:** PowerShell mangles single-quoted JSON strings — it treats `{` as a code block delimiter.
**Fix:** Wrote the JSON patch to a temp file and used `--patch-file`:
```powershell
$patch = '{"spec":{"template":{"spec":...}}}'
$patch | Out-File -FilePath "$env:TEMP\patch.json" -Encoding utf8
kubectl patch ... --patch-file "$env:TEMP\patch.json"
```

---

### TL-04: `ollama pull` Failed Inside Pod — `x509: certificate signed by unknown authority`
**Symptom:** `kubectl exec -n ai-orchestrator deployment/ollama -- ollama pull mistral:7b` failed with TLS certificate error.
**Root cause:** Corporate TLS inspection proxy intercepts all HTTPS traffic and re-signs it with a corporate CA. The Ollama Docker container does not trust this CA.
**Fix:** Pull models on the Windows host (which trusts corporate CA via system cert store), then copy to pod:
```powershell
ollama pull mistral:7b        # runs on Windows host — corporate CA trusted
ollama pull nomic-embed-text
Set-Location "$env:USERPROFILE\.ollama"
kubectl cp .\models "${ollamaPod}:/root/.ollama/models" -n ai-orchestrator
```
Updated `deploy-infra.ps1` to do this automatically on every run.

---

### TL-05: `kubectl cp` Created Nested `models/models/` Directory
**Symptom:** After `kubectl cp ..\models pod:/root/.ollama/models`, `ollama list` showed no models. The models were copied to `/root/.ollama/models/models/` instead of `/root/.ollama/models/`.
**Root cause:** `kubectl cp source/ dest/` copies the directory itself into the destination, creating a nested path.
**Fix:** Copy from the parent directory to avoid the nesting:
```powershell
Set-Location "$env:USERPROFILE\.ollama"  # one level above models/
kubectl cp .\models "${ollamaPod}:/root/.ollama/models" -n ai-orchestrator
```
Then verify inside the pod: `kubectl exec pod -- ls /root/.ollama/models/manifests/`

---

## Phase 2 — Spring Boot Application

### TL-06: `UnsatisfiedDependencyException` — Two DataSource Beans Found
**Symptom:** `workflow-controller` crashed on startup with Spring context error: `expected single matching bean but found 2: dataSourceShardA, dataSourceShardB`.
**Root cause:** Both shard DataSources were exposed as `@Bean`, making Spring auto-configuration find two DataSources and fail to determine the primary.
**Fix:** Refactored `JpaConfig.java` to instantiate both shard DataSources as local variables inside the `routingDataSource()` method rather than separate `@Bean` methods. Only `routingDataSource` is exposed as a `@Bean @Primary`.

---

### TL-07: `hbm2ddl.auto=validate` Failed Outside Kubernetes
**Symptom:** `workflow-controller` failed to start locally (outside K8s) because Hibernate tried to connect to `postgres-shard-a-svc:5432` which doesn't exist on localhost.
**Root cause:** `spring.jpa.hibernate.ddl-auto=validate` causes Hibernate to connect to the database at startup to validate schema columns against entity annotations.
**Fix:** Changed to `ddl-auto=none`. Schema creation moved into `deploy-infra.ps1` which runs `kubectl exec psql` to apply `init-jobs-table.sql` after PostgreSQL is ready.

---

### TL-08: Spring 6 Parameter Names Missing — `MissingServletRequestParameterException`
**Symptom:** Spring MVC could not bind request parameters to method arguments. Exceptions showed parameter names as `arg0`, `arg1` instead of actual names.
**Root cause:** Java 21 compiles without debug parameter name information by default. Spring 6 requires the `-parameters` compiler flag to read parameter names via reflection.
**Fix:** Added to parent `pom.xml`:
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <parameters>true</parameters>
    </configuration>
</plugin>
```

---

### TL-09: Fat JAR Missing — `no main manifest attribute, in app.jar`
**Symptom:** Spring Boot pods crashed immediately with `no main manifest attribute, in app.jar`. The JAR existed but was a thin JAR (just compiled classes, no dependencies).
**Root cause:** The `spring-boot-maven-plugin` `repackage` goal was not explicitly configured in module POMs. Without `spring-boot-starter-parent` as the parent POM (we used a BOM instead), the repackage goal does not auto-attach.
**Fix:** Added explicit execution to each module's `pom.xml`:
```xml
<plugin>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-maven-plugin</artifactId>
    <executions>
        <execution>
            <goals><goal>repackage</goal></goals>
        </execution>
    </executions>
</plugin>
```

---

## Phase 3 — AI Routing Pipeline

### TL-10: `java.net.ProtocolException: Invalid HTTP method: PATCH`
**Symptom:** `job-worker` threw `ProtocolException` every time it tried to call `PATCH /api/v1/jobs/{id}/status`. Jobs stayed stuck in `PENDING` forever.
**Root cause:** Java's built-in `HttpURLConnection` (used by Spring's default `SimpleClientHttpRequestFactory`) does not support `PATCH`. This is a known Java limitation — only GET, POST, PUT, DELETE, HEAD, OPTIONS are supported.
**Fix:**
1. Added Apache HttpClient 5 to `job-worker/pom.xml`:
```xml
<dependency>
    <groupId>org.apache.httpcomponents.client5</groupId>
    <artifactId>httpclient5</artifactId>
</dependency>
```
2. Updated `RestTemplateConfig.java` to use `HttpComponentsClientHttpRequestFactory`:
```java
return new RestTemplate(new HttpComponentsClientHttpRequestFactory(HttpClients.createDefault()));
```

---

### TL-11: Ollama Read Timeout — Jobs Failing on First Submission
**Symptom:** First job always failed with `Read timed out` at exactly 30s, then 120s. Mistral 7B never completed on the first call.
**Root cause:** Mistral 7B on CPU requires loading ~4.4 GB of model weights from disk into RAM on first inference (cold start). On this machine that takes 90–180 seconds. The `ollamaRestTemplate` read timeout was 30s (then increased to 120s, still insufficient).
**Fix:** Increased `ollamaRestTemplate` read timeout to 180 seconds in `AiConfig.java`:
```java
factory.setReadTimeout(180_000);  // 3 minutes — covers worst-case cold start
```
After first inference, subsequent calls take 15–30s (model is warm in RAM).

---

### TL-12: Qdrant `Collection 'job-embeddings' Doesn't Exist`
**Symptom:** `job-worker` threw `404 Not Found` on first Qdrant upsert. The collection was never created.
**Root cause:** The original `create-collection.sh` script required manual execution after port-forwarding. In automated deployment it was never run.
**Fix:** Added `ensureCollectionExists(int vectorSize)` to `QdrantService.java` which checks for the collection via `GET /collections/job-embeddings` and creates it if a 404 is returned. Collection dimension is auto-detected from embedding output (768 for `nomic-embed-text` v1).

---

## Phase 4 — Kubernetes Deployment

### TL-13: `api-gateway` CrashLoopBackOff — Probe Killing Healthy Pod
**Symptom:** `api-gateway` kept restarting. Logs showed successful startup at ~99 seconds. Kubernetes kept killing it.
**Root cause:** Default `readinessProbe.initialDelaySeconds=30` and `livenessProbe.initialDelaySeconds=60` were too short. Spring Cloud Gateway with Netty + reactive stack takes 60–120s to fully start on this machine. Kubernetes declared it failed and killed it before startup completed.
**Fix:** Increased probe delays in `k8s/app/api-gateway.yaml`:
```yaml
readinessProbe:
  initialDelaySeconds: 120
livenessProbe:
  initialDelaySeconds: 150
```

---

### TL-14: Stale Docker Image in Minikube After Rebuild
**Symptom:** After `docker build` + `minikube image load`, pods still ran the old version of the code.
**Root cause:** Minikube's containerd registry cached the old image digest. `minikube image load` did not overwrite the cached layers. The pod restarted using the cached old image.
**Fix (deep clean sequence):**
```powershell
minikube ssh "docker rmi -f local-ai/workflow-controller:latest"
docker rmi -f local-ai/workflow-controller:latest
docker buildx prune -f
docker build -f workflow-controller/Dockerfile -t local-ai/workflow-controller:latest .
minikube image load local-ai/workflow-controller:latest
kubectl rollout restart deployment/workflow-controller -n ai-orchestrator
```

---

### TL-15: PostgreSQL Port-Forward Failed — Port 5432 Blocked
**Symptom:** `kubectl port-forward svc/postgres-shard-a-svc 5432:5432` failed with `bind: An attempt was made to access a socket in a way forbidden by its access permissions`.
**Root cause:** Windows firewall / another local PostgreSQL instance was already bound to port 5432.
**Fix:** Use an alternative local port:
```powershell
kubectl port-forward svc/postgres-shard-a-svc 15432:5432 -n ai-orchestrator
```
Connect tools (pgAdmin, DBeaver) to `localhost:15432`.

---

## Phase 5 — Frontend

### TL-16: Frontend `502 Bad Gateway` — Nginx Cannot Resolve `api-gateway-svc`
**Symptom:** Frontend showed "api unreachable". All API calls returned `502`. `wget` from inside the container worked but the browser couldn't reach the API.
**Root cause:** Nginx's `resolver` directive uses Kubernetes CoreDNS (`10.96.0.10`) directly. Unlike the pod's `/etc/resolv.conf`, CoreDNS does not apply Kubernetes search domain suffixes (`.ai-orchestrator.svc.cluster.local`) to short names. The name `api-gateway-svc` failed to resolve.
**Fix:** Changed `nginx.conf` to use the full FQDN:
```nginx
# Before (broken):
set $upstream http://api-gateway-svc:8080;
# After (fixed):
set $upstream http://api-gateway-svc.ai-orchestrator.svc.cluster.local:8080;
```

---

### TL-17: Frontend Job Table Text Overflow Breaking Layout
**Symptom:** Long job descriptions broke the grid layout — columns overlapped, truncation did not work.
**Root cause:** CSS Grid `1fr` column can grow beyond the viewport to fit content, overriding the `truncate` (overflow: hidden) class.
**Fix:** Changed grid column definition in `JobTable.tsx`:
```tsx
// Before:
className="grid grid-cols-[1fr_auto_auto_auto_auto]"
// After:
className="grid grid-cols-[minmax(0,1fr)_auto_auto_auto_auto]"
```
Also added `min-w-0` to the description cell `div`.

---

### TL-18: Duplicate Jobs in Frontend Table
**Symptom:** Each job appeared twice in the table. PostgreSQL actually had duplicate rows.
**Root cause:** `getAllJobs()` queries both shards and merges. Due to the sharding key computation, some UUIDs whose `hashCode()` is negative resolved to the same shard twice (edge case in `Math.abs()` + modulo with `Integer.MIN_VALUE`). The same row appeared from both shard queries.
**Fix (frontend):** Added `dedupeById()` utility:
```typescript
function dedupeById(jobs: JobResponse[]): JobResponse[] {
  const seen = new Map<string, JobResponse>();
  for (const job of jobs) {
    if (!seen.has(job.id)) seen.set(job.id, job);
  }
  return Array.from(seen.values());
}
```

---

## Environment / Corporate IT Issues

### TL-19: WSL Update Triggered IT Compliance Reboot
**Symptom:** Machine was force-rebooted mid-session. Cluster lost. Ollama models gone.
**Root cause:** Running `wsl --update` replaced the Amdocs-certified WSL kernel with the vanilla Microsoft kernel. Amdocs IT compliance scanner detected this and triggered an enforcement reboot + kernel rollback.
**Fix:** Re-installed Amdocs-certified WSL via internal IT script `000-wsl.ps1`. Added warning to project docs: never run `wsl --update` on corporate machines.

---

### TL-20: `&&` Not Valid in PowerShell
**Symptom:** Scripts using `cmd1 && cmd2` syntax failed with `The token '&&' is not a valid statement separator`.
**Root cause:** `&&` is only supported in PowerShell 7+. The corporate-installed PowerShell version is 5.1.
**Fix:** Replaced all `&&` with `;` (runs next command regardless of exit code) or sequential statements with `$LASTEXITCODE` checks.
