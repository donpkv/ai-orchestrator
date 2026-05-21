import { useCallback, useEffect, useState } from "react";
import { api } from "./api";
import type { JobResponse } from "./types";
import { Stats } from "./components/Stats";
import { JobForm } from "./components/JobForm";
import { JobTable } from "./components/JobTable";

const POLL_INTERVAL_MS = 3000;
const STATUS_FILTERS = ["ALL", "PENDING", "ROUTED", "COMPLETED", "FAILED"] as const;
type StatusFilter = typeof STATUS_FILTERS[number];

function dedupeById(jobs: JobResponse[]): JobResponse[] {
  const seen = new Map<string, JobResponse>();
  for (const job of jobs) {
    // keep the latest version of each job (list is already sorted newest-first)
    if (!seen.has(job.id)) seen.set(job.id, job);
  }
  return Array.from(seen.values());
}

export default function App() {
  const [jobs, setJobs] = useState<JobResponse[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [lastSync, setLastSync] = useState<Date | null>(null);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("ALL");

  const refresh = useCallback(async () => {
    try {
      const data = await api.listJobs();
      const sorted = [...data].sort(
        (a, b) =>
          new Date(b.submittedAt).getTime() - new Date(a.submittedAt).getTime(),
      );
      setJobs(dedupeById(sorted));
      setError(null);
      setLastSync(new Date());
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, []);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, POLL_INTERVAL_MS);
    return () => clearInterval(id);
  }, [refresh]);

  function handleSubmitted(job: JobResponse) {
    setJobs((prev) => dedupeById([job, ...prev.filter((j) => j.id !== job.id)]));
    refresh();
  }

  const filteredJobs =
    statusFilter === "ALL" ? jobs : jobs.filter((j) => j.status === statusFilter);

  return (
    <div className="min-h-screen px-6 py-10 max-w-6xl mx-auto">
      <header className="flex items-center justify-between mb-10">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight bg-gradient-to-r from-indigo-300 via-fuchsia-300 to-amber-300 bg-clip-text text-transparent">
            AI Orchestrator
          </h1>
          <p className="text-sm text-slate-500 mt-1">
            Kubernetes &middot; Sharded Postgres &middot; Vector cache &middot;
            Mistral 7B routing
          </p>
        </div>
        <div className="flex items-center gap-2 text-xs text-slate-500">
          {error ? (
            <span className="flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-rose-400" />
              api unreachable
            </span>
          ) : (
            <span className="flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
              live &middot;{" "}
              {lastSync ? `synced ${lastSync.toLocaleTimeString()}` : "syncing..."}
            </span>
          )}
        </div>
      </header>

      <section className="mb-6">
        <Stats jobs={jobs} />
      </section>

      {/* Status filter bar */}
      <div className="flex gap-2 mb-4 flex-wrap">
        {STATUS_FILTERS.map((f) => (
          <button
            key={f}
            onClick={() => setStatusFilter(f)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
              statusFilter === f
                ? "bg-indigo-500 text-white"
                : "bg-slate-800 text-slate-400 hover:bg-slate-700 hover:text-slate-200"
            }`}
          >
            {f}
            {f !== "ALL" && (
              <span className="ml-1.5 opacity-60">
                {jobs.filter((j) => j.status === f).length}
              </span>
            )}
          </button>
        ))}
      </div>

      <section className="grid lg:grid-cols-[400px_1fr] gap-6">
        <JobForm onSubmitted={handleSubmitted} />
        <JobTable jobs={filteredJobs} />
      </section>

      {error && (
        <div className="mt-6 text-sm text-rose-300 bg-rose-500/10 border border-rose-500/30 rounded-lg p-4">
          <div className="font-medium mb-1">Cannot reach API gateway</div>
          <div className="text-xs text-rose-200/80 font-mono">{error}</div>
          <div className="text-xs text-rose-200/60 mt-2">
            Make sure the cluster is up and the api-gateway NodePort is
            reachable. Default dev proxy target: <code>http://localhost:30080</code>.
          </div>
        </div>
      )}
    </div>
  );
}
