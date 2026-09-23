import { useCallback, useEffect, useState } from "react";

import { useAuth } from "./auth";
import { adapters, type ChannelId } from "./marketplaces";
import { supabase } from "./supabase";

/**
 * Which channels this seller has connected.
 *
 * The row lives in public.connections and carries nothing secret. The OAuth
 * tokens are in public.channel_credentials, which has RLS on and no policies at
 * all - only the backend's service role can read them. The device is never meant
 * to see a marketplace token, so it cannot.
 *
 * Rows are written by the backend at the end of the OAuth round trip; the app
 * only reads them and can delete its own.
 */
export type Connection = {
  id: string;
  channel: ChannelId;
  label: string | null;
  status: "active" | "expired" | "revoked";
  connected_at: string;
};

export function useConnections() {
  const { user } = useAuth();
  const [connections, setConnections] = useState<Connection[]>([]);
  const [isLoading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    if (!user) {
      setConnections([]);
      setLoading(false);
      return;
    }
    const { data, error } = await supabase
      .from("connections")
      .select("id, channel, label, status, connected_at")
      .eq("user_id", user.id);

    if (error) console.error("connections load failed", error);
    setConnections((data as Connection[] | null) ?? []);
    setLoading(false);
  }, [user]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const isConnected = useCallback(
    (channel: ChannelId) => {
      const adapter = adapters.find((a) => a.id === channel);
      if (adapter && !adapter.requiresConnection) return true;
      return connections.some((c) => c.channel === channel && c.status === "active");
    },
    [connections],
  );

  const disconnect = useCallback(
    async (channel: ChannelId) => {
      if (!user) return;
      const { error } = await supabase
        .from("connections")
        .delete()
        .eq("user_id", user.id)
        .eq("channel", channel);
      if (error) throw error;
      await refresh();
    },
    [user, refresh],
  );

  return { connections, isConnected, disconnect, isLoading, refresh };
}
