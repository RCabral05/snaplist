import { useEffect, useState } from "react";

import { supabase } from "./supabase";

export const USERNAME_MIN = 3;
export const USERNAME_MAX = 20;
const SHAPE = /^[A-Za-z0-9_]+$/;

export type UsernameStatus =
  | { kind: "empty" }
  | { kind: "too-short" }
  | { kind: "too-long" }
  | { kind: "invalid" }
  | { kind: "unchanged" }
  | { kind: "checking" }
  | { kind: "available" }
  | { kind: "taken" }
  | { kind: "error"; message: string };

/**
 * Everything that can be judged without the server. Returns null when the
 * candidate is well formed, which is the only case worth a round trip - there is
 * no reason to ask whether "a b" is a legal username.
 */
function localStatus(value: string, current?: string | null): UsernameStatus | null {
  if (!value) return { kind: "empty" };
  if (current && value.toLowerCase() === current.toLowerCase()) return { kind: "unchanged" };
  if (!SHAPE.test(value)) return { kind: "invalid" };
  if (value.length < USERNAME_MIN) return { kind: "too-short" };
  if (value.length > USERNAME_MAX) return { kind: "too-long" };
  return null;
}

/**
 * Live availability, debounced.
 *
 * The answer is tagged with the text it was asked about, so a slow reply that
 * lands after the field has moved on is simply not the answer to the current
 * question and is ignored. That tag also keeps the local verdict out of state
 * entirely: it is derived during render, and the effect only ever deals with
 * the network.
 *
 * Pass `current` when renaming. username_available() counts every row including
 * the seller's own, so without it their existing name reports back as taken the
 * moment the edit screen opens - technically true, and useless to say.
 */
export function useUsernameCheck(
  raw: string,
  current?: string | null,
  delay = 350,
): UsernameStatus {
  const value = raw.trim();
  const local = localStatus(value, current);
  const [answer, setAnswer] = useState<{ for: string; status: UsernameStatus } | null>(null);

  // A boolean, not `local` itself: that object is rebuilt every render and would
  // restart the debounce on each keystroke-driven re-render.
  const needsServer = local === null;

  useEffect(() => {
    if (!needsServer) return; // nothing the server can add

    const timer = setTimeout(async () => {
      const { data, error } = await supabase.rpc("username_available", { candidate: value });
      setAnswer({
        for: value,
        status: error
          ? { kind: "error", message: error.message }
          : { kind: data ? "available" : "taken" },
      });
    }, delay);

    return () => clearTimeout(timer);
  }, [value, needsServer, delay]);

  if (local) return local;
  if (answer?.for === value) return answer.status;
  return { kind: "checking" };
}

export function usernameHint(status: UsernameStatus): string {
  switch (status.kind) {
    case "empty":
      return "Letters, numbers and underscores.";
    case "too-short":
      return "At least " + USERNAME_MIN + " characters.";
    case "too-long":
      return "At most " + USERNAME_MAX + " characters.";
    case "invalid":
      return "Letters, numbers and underscores only.";
    case "unchanged":
      return "This is your username.";
    case "checking":
      return "Checking…";
    case "available":
      return "Available";
    case "taken":
      return "Taken";
    case "error":
      return "Could not check right now.";
  }
}
