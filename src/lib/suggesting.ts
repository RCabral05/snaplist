import { useSyncExternalStore } from "react";

/**
 * Which drafts are waiting on the model right now.
 *
 * The work starts on the camera screen and finishes while the editor is open, so
 * neither screen owns the state and it does not belong on either. It is
 * deliberately in memory only: if the app is killed mid-suggestion the request
 * dies with it, so a flag that survived a restart would be a lie.
 */
const pending = new Set<string>();
const listeners = new Set<() => void>();

const emit = () => listeners.forEach((l) => l());

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

export function markSuggesting(listingId: string) {
  pending.add(listingId);
  emit();
}

export function clearSuggesting(listingId: string) {
  pending.delete(listingId);
  emit();
}

/** useSyncExternalStore, so subscribing never writes state during an effect. */
export function useIsSuggesting(listingId?: string): boolean {
  return useSyncExternalStore(
    subscribe,
    () => (listingId ? pending.has(listingId) : false),
    () => false,
  );
}
