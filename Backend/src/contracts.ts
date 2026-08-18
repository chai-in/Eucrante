export const presetNames = [
  "apple-music-best",
  "apple-music-efficient",
  "apple-video-best",
  "apple-video-efficient",
  "custom",
] as const;

export type PresetName = (typeof presetNames)[number];
export type JobState = "resolving" | "resolved" | "uploading" | "completed" | "failed";

export interface JobArtifact {
  slot: string;
  role: "input" | "output";
  key: string;
  size: number;
  etag: string;
  contentType?: string;
}

export interface JobManifest {
  schemaVersion: 1;
  id: string;
  state: JobState;
  preset: PresetName;
  sourceHost: string;
  createdAt: string;
  updatedAt: string;
  artifacts: JobArtifact[];
  errorCode?: string;
}

export interface CreateJobBody {
  request: Record<string, unknown> & { url: string };
  preset?: PresetName;
}

export interface CompleteUploadBody {
  uploadId: string;
  parts: Array<{ partNumber: number; etag: string }>;
}
