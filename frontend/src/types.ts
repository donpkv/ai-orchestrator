export type JobStatus = "PENDING" | "ROUTED" | "COMPLETED" | "FAILED";

export interface JobResponse {
  id: string;
  description: string;
  priority: number;
  status: JobStatus;
  shardKey: string;
  workerType: string | null;
  routingDecision?: string | null;
  submittedAt: string;
}

export interface JobRequest {
  description: string;
  priority: number;
}
