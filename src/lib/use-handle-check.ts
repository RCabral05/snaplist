import { useEffect, useState } from "react";

import { supabase } from "./supabase";

export const HANDLE_MIN = 3;
export const HANDLE_MAX = 20;
const SHAPE = /^[A-Za-z0-9_]+$/;

export type HandleStatus =
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
 * no reason to ask whether "a b" is a legal handle.
 */
function localStatus(value: string, current?: string | null): HandleStatus | null {
  if (!value) return { kind: "empty" };
  if (current && value.toLowerCase() === current.toLowerCase()) return { kind: "unchanged" };
  if (!SHAPE.test(value)) return { kind: "invalid" };
  if (value.length < HANDLE_MIN) return { kind: "too-short" };
  if (value.length > HANDLE_MAX) return { kind: "too-long" };
  return null;
}

/**
 * Live availability for a claimable handle, debounced.
 *
 * `rpc` is a security-definer function returning one boolean, because the table
 * behind it is never readable across rows - the whole reason availability cannot
 * be checked with a plain select. Brands use brand_slug_available.
 *
 * The answer is tagged with the text it was asked about, so a slow reply landing
 * after the field has moved on is simply not the answer to the current question.
 * Pass `current` when renaming, or the holder's own handle reports back as taken.
 */
export function useHandleCheck(
  raw: string,
  rpc: string,
  current?: string | null,
  delay = 350,
): HandleStatus {
  const value = raw.trim();
  const local = localStatus(value, current);
  const [answer, setAnswer] = useState<{ for: string; status: HandleStatus } | null>(null);

  // A boolean, not `local` itself: that object is rebuilt every render and would
  // restart the debounce on each keystroke-driven re-render.
  const needsServer = local === null;

  useEffect(() => {
    if (!needsServer) return;

    const timer = setTimeout(async () => {
      const { data, error } = await supabase.rpc(rpc, { candidate: value });
      setAnswer({
        for: value,
        status: error
          ? { kind: "error", message: error.message }
          : { kind: data ? "available" : "taken" },
      });
    }, delay);

    return () => clearTimeout(timer);
  }, [value, needsServer, rpc, delay]);

  if (local) return local;
  if (answer && answer.for === value) return answer.status;
  return { kind: "checking" };
}

export function handleHint(status: HandleStatus, noun = "handle"): string {
  switch (status.kind) {
    case "empty":
      return "Letters, numbers and underscores.";
    case "too-short":
      return "At least " + HANDLE_MIN + " characters.";
    case "too-long":
      return "At most " + HANDLE_MAX + " characters.";
    case "invalid":
      return "Letters, numbers and underscores only.";
    case "unchanged":
      return `This is your ${noun}.`;
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
