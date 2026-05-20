import { useState } from "react";
import type { JobResponse } from "../types";
import { StatusBadge } from "./StatusBadge";

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const s = Math.floor(diff / 1000);
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

function ShardPill({ shardKey }: { shardKey: string }) {
  const isA = shardKey === "shard-a" || shardKey === "0";
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-mono uppercase ${
        isA
          ? "bg-violet-500/15 text-violet-300"
          : "bg-fuchsia-500/15 text-fuchsia-300"
      }`}
    >
      {shardKey || "?"}
    </span>
  );
}

export function JobTable({ jobs }: { jobs: JobResponse[] }) {
  const [expanded, setExpanded] = useState<string | null>(null);

  if (jobs.length === 0) {
    return (
      <div className="glass p-12 text-center text-slate-500">
        No jobs yet. Submit one above to get started.
      </div>
    );
  }

  return (
    <div className="glass overflow-hidden">
      <div className="grid grid-cols-[1fr_auto_auto_auto_auto] gap-4 px-5 py-3 text-xs uppercase tracking-wider text-slate-500 border-b border-slate-800/60">
        <div>Description</div>
        <div>Status</div>
        <div>Worker</div>
        <div>Shard</div>
        <div>Submitted</div>
      </div>
      <div className="divide-y divide-slate-800/40">
        {jobs.map((job) => {
          const isExpanded = expanded === job.id;
          return (
            <div key={job.id}>
              <button
                onClick={() => setExpanded(isExpanded ? null : job.id)}
                className="w-full grid grid-cols-[1fr_auto_auto_auto_auto] gap-4 px-5 py-3 text-left hover:bg-slate-800/30 transition-colors items-center"
              >
                <div className="truncate text-slate-200">{job.description}</div>
                <StatusBadge status={job.status} />
                <div className="text-xs font-mono text-slate-400">
                  {job.workerType ?? "—"}
                </div>
                <ShardPill shardKey={job.shardKey} />
                <div className="text-xs text-slate-500 whitespace-nowrap">
                  {timeAgo(job.submittedAt)}
                </div>
              </button>
              {isExpanded && (
                <div className="px-5 py-4 bg-slate-900/40 text-xs space-y-2 font-mono">
                  <div>
                    <span className="text-slate-500">id: </span>
                    <span className="text-slate-300">{job.id}</span>
                  </div>
                  <div>
                    <span className="text-slate-500">priority: </span>
                    <span className="text-slate-300">{job.priority}</span>
                  </div>
                  <div>
                    <span className="text-slate-500">submittedAt: </span>
                    <span className="text-slate-300">{job.submittedAt}</span>
                  </div>
                  {job.routingDecision && (
                    <div>
                      <span className="text-slate-500">routing decision: </span>
                      <span className="text-slate-300 whitespace-pre-wrap">
                        {job.routingDecision}
                      </span>
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
