import type { JobResponse, JobStatus } from "../types";

interface StatCardProps {
  label: string;
  value: number | string;
  accent: string;
}

function StatCard({ label, value, accent }: StatCardProps) {
  return (
    <div className="glass p-5">
      <div className="text-xs uppercase tracking-wider text-slate-400 mb-1">
        {label}
      </div>
      <div className={`text-3xl font-semibold ${accent}`}>{value}</div>
    </div>
  );
}

export function Stats({ jobs }: { jobs: JobResponse[] }) {
  const count = (s: JobStatus) => jobs.filter((j) => j.status === s).length;
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
      <StatCard label="Total" value={jobs.length} accent="text-slate-100" />
      <StatCard label="Pending" value={count("PENDING")} accent="text-amber-300" />
      <StatCard label="Routed" value={count("ROUTED")} accent="text-sky-300" />
      <StatCard
        label="Completed"
        value={count("COMPLETED")}
        accent="text-emerald-300"
      />
    </div>
  );
}
