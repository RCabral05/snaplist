import { useEffect, useRef, useState } from "react";

import { supabase } from "./supabase";

export const USERNAME_MIN = 3;
export const USERNAME_MAX = 20;
const SHAPE = /^[A-Za-z0-9_]+$/;

export type UsernameStatus =
  | { kind: "empty" }
  | { kind: "too-short" }
  | { kind: "too-long" }
  | { kind: "invalid" }
  | { kind: "checking" }
  | { kind: "available" }
  | { kind: "taken" }
  | { kind: "error"; message: string };

/**
 * Live availability, debounced.
 *
 * Shape is judged locally and instantly - there is no reason to ask the server
 * whether "a b" is a legal username. Only well-formed candidates cost a round
 * trip, and a sequence number drops the answer to any query the user has already
 * typed past, so a slow early response cannot overwrite a fast later one.
 */
export function useUsernameCheck(raw: string, delay = 350): UsernameStatus {
  const [status, setStatus] = useState<UsernameStatus>({ kind: "empty" });
  const seq = useRef(0);

  useEffect(() => {
    const value = raw.trim();
    const ticket = ++seq.current;

    if (!value) return setStatus({ kind: "empty" });
    if (!SHAPE.test(value)) return setStatus({ kind: "invalid" });
    if (value.length < USERNAME_MIN) return setStatus({ kind: "too-short" });
    if (value.length > USERNAME_MAX) return setStatus({ kind: "too-long" });

    setStatus({ kind: "checking" });

    const timer = setTimeout(async () => {
      const { data, error } = await supabase.rpc("username_available", { candidate: value });
      if (ticket !== seq.current) return; // the field moved on; this answer is stale
      if (error) return setStatus({ kind: "error", message: error.message });
      setStatus({ kind: data ? "available" : "taken" });
    }, delay);

    return () => clearTimeout(timer);
  }, [raw, delay]);

  return status;
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
