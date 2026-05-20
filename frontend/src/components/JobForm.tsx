import { useState } from "react";
import { api } from "../api";
import type { JobResponse } from "../types";

interface Props {
  onSubmitted: (job: JobResponse) => void;
}

const SAMPLES = [
  "Generate weekly inventory report for warehouse A",
  "Analyze customer churn from last quarter",
  "Reconcile bank statements for fiscal year end",
  "Process daily sales report for Q1 2024",
];

export function JobForm({ onSubmitted }: Props) {
  const [description, setDescription] = useState("");
  const [priority, setPriority] = useState(5);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!description.trim()) return;
    setSubmitting(true);
    setError(null);
    try {
      const job = await api.submitJob({ description: description.trim(), priority });
      onSubmitted(job);
      setDescription("");
      setPriority(5);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="glass p-6 space-y-4">
      <div>
        <label className="block text-sm font-medium text-slate-300 mb-2">
          Job description
        </label>
        <textarea
          className="input min-h-[88px] resize-none"
          placeholder="Describe the task in natural language..."
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          maxLength={500}
        />
        <div className="flex flex-wrap gap-2 mt-2">
          {SAMPLES.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setDescription(s)}
              className="text-xs px-2 py-1 rounded-md bg-slate-800/60 hover:bg-slate-700/60 text-slate-400 hover:text-slate-200 transition-colors"
            >
              {s}
            </button>
          ))}
        </div>
      </div>

      <div className="flex items-center gap-4">
        <label className="text-sm font-medium text-slate-300 whitespace-nowrap">
          Priority
        </label>
        <input
          type="range"
          min={1}
          max={10}
          value={priority}
          onChange={(e) => setPriority(Number(e.target.value))}
          className="flex-1 accent-indigo-500"
        />
        <span className="text-sm font-mono w-8 text-right text-indigo-300">
          {priority}
        </span>
      </div>

      {error && (
        <div className="text-sm text-rose-300 bg-rose-500/10 border border-rose-500/30 rounded-lg px-3 py-2">
          {error}
        </div>
      )}

      <button
        type="submit"
        className="btn-primary w-full"
        disabled={submitting || !description.trim()}
      >
        {submitting ? "Submitting..." : "Submit job"}
      </button>
    </form>
  );
}
