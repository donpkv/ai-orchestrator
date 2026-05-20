# Phase 2: Virtual threads (Java 21)

## Platform threads

A **platform thread** is a one-to-one mapping to an operating-system thread. Each platform thread needs its own stack (often on the order of ~1 MB by default) and kernel resources. For that reason, a JVM process can only host a practical upper bound of roughly **200–500** platform threads before memory pressure, context switching, and scheduler limits become painful. Work is scheduled by the OS; the thread is “heavy.”

## Virtual threads

A **virtual thread** is a lightweight thread managed by the JVM: it is **not** tied 1:1 to an OS thread for its whole lifetime. When a virtual thread blocks (for example on I/O), the carrier platform thread can run other virtual threads. Stacks are small (on the order of a few kilobytes in typical use), and the model is designed so you can have **millions** of virtual threads without dedicating millions of OS threads. Scheduling maps many virtual threads onto a smaller pool of platform threads.

## Why this matters for this project

In **workflow-controller**, each HTTP request can run on its own virtual thread instead of competing for a fixed Tomcat worker pool. In **job-worker**, each Kafka listener callback can run on a virtual thread via `SimpleAsyncTaskExecutor` backed by `Thread.ofVirtual().factory()`, instead of being limited by a fixed listener thread pool. Together, **concurrency is less constrained by pool size** while still using blocking-style code (JDBC, Redis, Kafka, HTTP clients)—you get scale for I/O-heavy work without manually tuning tiny thread pools for every integration.

## `Executors.newVirtualThreadPerTaskExecutor()` vs a fixed thread pool

- **`Executors.newVirtualThreadPerTaskExecutor()`**: submits each task on a **new virtual thread**. There is no fixed cap on how many tasks can be “in flight” from the executor’s perspective; backing resources (sockets, DB connections, memory) still limit real throughput. Ideal when tasks spend time **waiting** on I/O.
- **Fixed thread pool**: a **bounded** number of platform threads runs all submitted work. If all threads are busy or blocked, new work queues or is rejected. Useful when you must cap concurrency (e.g., protect a scarce resource) or for CPU-bound work where more threads than cores rarely helps.

## When virtual threads help (and when they do not)

- **Good fit — I/O-bound work**: PostgreSQL queries, Redis calls, Kafka produce/consume handlers, outbound HTTP. These workloads often block; virtual threads let many operations wait concurrently without hoarding OS threads.
- **Poor fit — CPU-bound work**: heavy computation, tight loops, parallel streams over large datasets on the same pool. Extra virtual threads do not create more CPU; you still want bounded parallelism (e.g., fork/join or a small fixed pool sized to cores) to avoid oversubscription.

## `spring.threads.virtual.enabled: true` (Spring Boot 3.2+)

In Spring Boot **3.2**, setting `spring.threads.virtual.enabled` to `true` turns on the framework’s **built-in virtual thread integration** for supported stacks (including embedded Tomcat for servlet stacks). Application components that Boot wires with virtual-thread–aware executors will use them where applicable.

In this repo we still define explicit beans (for example `TomcatProtocolHandlerCustomizer` in workflow-controller and the Kafka listener task executor in job-worker) as a **belt-and-suspenders** guarantee alongside that property, so behavior is clear and resilient to version or auto-configuration nuances.
