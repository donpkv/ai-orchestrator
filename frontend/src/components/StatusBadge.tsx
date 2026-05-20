import type { JobStatus } from "../types";

const styles: Record<JobStatus, string> = {
  PENDING: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  ROUTED: "bg-sky-500/15 text-sky-300 border-sky-500/30",
  COMPLETED: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  FAILED: "bg-rose-500/15 text-rose-300 border-rose-500/30",
};

const dots: Record<JobStatus, string> = {
  PENDING: "bg-amber-400 animate-pulse",
  ROUTED: "bg-sky-400 animate-pulse",
  COMPLETED: "bg-emerald-400",
  FAILED: "bg-rose-400",
};

export function StatusBadge({ status }: { status: JobStatus }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium ${styles[status]}`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${dots[status]}`} />
      {status}
    </span>
  );
}
