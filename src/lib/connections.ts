import { useCallback, useEffect, useMemo, useState } from "react";

import { useBrands } from "./brands";
import { adapters, type ChannelId } from "./marketplaces";
import { supabase } from "./supabase";

/**
 * Which channels the active brand has connected.
 *
 * A connection belongs to a brand, not to an account: @nike's eBay account is
 * not some other brand's, and the unique constraint is on (brand_id, channel)
 * so each brand connects independently.
 *
 * The row carries nothing secret. The OAuth tokens are in
 * public.channel_credentials, which has RLS on and no policies at all - only the
 * backend's service role can read them. The device is never meant to see a
 * marketplace token, so it cannot.
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

/** Stable identity, so "no connections" does not look like a new value each render. */
const EMPTY: Connection[] = [];

async function fetchConnections(brandId: string): Promise<Connection[]> {
  const { data, error } = await supabase
    .from("connections")
    .select("id, channel, label, status, connected_at")
    .eq("brand_id", brandId);
  if (error) throw error;
  return (data as Connection[] | null) ?? [];
}

export function useConnections() {
  const { active } = useBrands();
  const brandId = active?.id;

  const [attempt, setAttempt] = useState(0);
  const [answer, setAnswer] = useState<{ key: string; rows: Connection[] } | null>(null);

  // Keyed by brand and attempt so "loading" is derived rather than set, and a
  // reply for the brand you just switched away from is simply not the answer to
  // the current question.
  const key = `${brandId ?? "none"}:${attempt}`;

  useEffect(() => {
    // No brand means nothing to fetch and nothing to store: the empty list is
    // derived below rather than written, so this effect never sets state
    // synchronously.
    if (!brandId) return;

    let alive = true;
    fetchConnections(brandId)
      .then((rows) => {
        if (alive) setAnswer({ key, rows });
      })
      .catch(() => {
        if (alive) setAnswer({ key, rows: [] });
      });
    return () => {
      alive = false;
    };
  }, [brandId, key]);

  const connections = useMemo(
    () => (brandId && answer?.key === key ? answer.rows : EMPTY),
    [brandId, answer, key],
  );
  const isLoading = !!brandId && answer?.key !== key;

  const refresh = useCallback(async () => {
    setAttempt((n) => n + 1);
  }, []);

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
      if (!brandId) return;
      const { error } = await supabase
        .from("connections")
        .delete()
        .eq("brand_id", brandId)
        .eq("channel", channel);
      if (error) throw error;
      setAttempt((n) => n + 1);
    },
    [brandId],
  );

  return { connections, isConnected, disconnect, isLoading, refresh };
}
