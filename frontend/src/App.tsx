import { useCallback, useEffect, useState } from "react";
import { api } from "./api";
import type { JobResponse } from "./types";
import { Stats } from "./components/Stats";
import { JobForm } from "./components/JobForm";
import { JobTable } from "./components/JobTable";

const POLL_INTERVAL_MS = 3000;

export default function App() {
  const [jobs, setJobs] = useState<JobResponse[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [lastSync, setLastSync] = useState<Date | null>(null);

  const refresh = useCallback(async () => {
    try {
      const data = await api.listJobs();
      const sorted = [...data].sort(
        (a, b) =>
          new Date(b.submittedAt).getTime() - new Date(a.submittedAt).getTime(),
      );
      setJobs(sorted);
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
    setJobs((prev) => [job, ...prev.filter((j) => j.id !== job.id)]);
    refresh();
  }

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

      <section className="grid lg:grid-cols-[400px_1fr] gap-6">
        <JobForm onSubmitted={handleSubmitted} />
        <JobTable jobs={jobs} />
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
