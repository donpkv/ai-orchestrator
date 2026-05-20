import type { JobRequest, JobResponse } from "./types";

const API_BASE = "/api/v1/jobs";

async function handle<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${res.status} ${res.statusText}: ${text}`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  async listJobs(): Promise<JobResponse[]> {
    const res = await fetch(API_BASE);
    return handle<JobResponse[]>(res);
  },

  async getJob(id: string): Promise<JobResponse> {
    const res = await fetch(`${API_BASE}/${id}`);
    return handle<JobResponse>(res);
  },

  async submitJob(req: JobRequest): Promise<JobResponse> {
    const res = await fetch(API_BASE, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req),
    });
    return handle<JobResponse>(res);
  },
};
