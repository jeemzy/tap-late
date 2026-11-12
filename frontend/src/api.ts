export type Region = {
  id: string;
  polygon: number[][];
  box: [number, number, number, number];
  raw_text: string;
  source: string;
  translation: string | null;
  confidence: number;
  background: string;
  foreground: string;
};
export type Session = {
  id: string;
  status: "queued" | "ocr" | "translating" | "ready" | "failed";
  created_at: number;
  expires_at: number;
  width: number;
  height: number;
  regions: Region[];
  original_url: string;
  annotated_url: string | null;
  view_url: string;
  error: string | null;
};
export type Health = {
  translation_configured: boolean;
  model: string;
  retention_days: number;
};
export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
  }
}
export async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new ApiError(
      typeof body.detail === "string"
        ? body.detail
        : `Request failed (${response.status}). Please try again.`,
      response.status,
    );
  }
  return response.status === 204 ? (undefined as T) : response.json();
}
export async function upload(file: File) {
  const form = new FormData();
  form.append("file", file);
  // The server generates a UUID when omitted; this also works on private HTTP origins.
  return request<{ id: string; view_url: string }>("/api/sessions", {
    method: "POST",
    body: form,
  });
}
export const busy = (session: Session) =>
  !["ready", "failed"].includes(session.status);
export const statusText = {
  queued: "Waiting to start",
  ocr: "Reading Chinese text",
  translating: "Translating in context",
  ready: "Ready to read",
  failed: "Needs another try",
};
