import Constants from "expo-constants";

/**
 * The backend is the only thing holding marketplace credentials. Every publish,
 * every OAuth handshake and every photo upload goes through it. Until it exists,
 * MOCK is on and the calls below resolve locally so the app is still walkable.
 */
export const API_URL: string =
  process.env.EXPO_PUBLIC_API_URL ??
  (Constants.expoConfig?.extra as { apiUrl?: string } | undefined)?.apiUrl ??
  "";

export const MOCK = !API_URL;

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export async function api<T>(path: string, init?: RequestInit & { token?: string }): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...((init?.headers as Record<string, string>) ?? {}),
  };
  if (init?.token) headers.Authorization = "Bearer " + init.token;

  const res = await fetch(API_URL + path, { ...init, headers });
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;

  if (!res.ok) throw new ApiError(res.status, body?.error ?? res.statusText);
  return body as T;
}
