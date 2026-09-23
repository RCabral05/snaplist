import AsyncStorage from "@react-native-async-storage/async-storage";
import { useCallback, useEffect, useState } from "react";

import { adapters, type ChannelId } from "./marketplaces";

/**
 * Which channels this seller has connected.
 *
 * Only the fact of a connection lives on the device. The OAuth tokens live on the
 * backend against the seller's account - a mobile binary is readable, so anything
 * shipped in it is public. See README.
 */
const KEY = "snaplist.connections.v1";

export type Connection = { channel: ChannelId; label?: string; connectedAt: string };

let cache: Connection[] | null = null;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

async function load(): Promise<Connection[]> {
  if (cache) return cache;
  const raw = await AsyncStorage.getItem(KEY);
  cache = raw ? (JSON.parse(raw) as Connection[]) : [];
  return cache;
}

async function save(next: Connection[]) {
  cache = next;
  await AsyncStorage.setItem(KEY, JSON.stringify(next));
  emit();
}

export async function connect(channel: ChannelId, label?: string) {
  const current = await load();
  const next = [
    ...current.filter((c) => c.channel !== channel),
    { channel, label, connectedAt: new Date().toISOString() },
  ];
  await save(next);
}

export async function disconnect(channel: ChannelId) {
  const current = await load();
  await save(current.filter((c) => c.channel !== channel));
}

export function useConnections() {
  const [connections, setConnections] = useState<Connection[]>(cache ?? []);
  const [isLoading, setLoading] = useState(!cache);

  const refresh = useCallback(() => {
    load().then((c) => {
      setConnections([...c]);
      setLoading(false);
    });
  }, []);

  useEffect(() => {
    refresh();
    const listener = () => setConnections([...(cache ?? [])]);
    listeners.add(listener);
    return () => { listeners.delete(listener); };
  }, [refresh]);

  const isConnected = useCallback(
    (channel: ChannelId) => {
      const adapter = adapters.find((a) => a.id === channel);
      if (adapter && !adapter.requiresConnection) return true;
      return connections.some((c) => c.channel === channel);
    },
    [connections],
  );

  return { connections, isConnected, isLoading, refresh };
}
