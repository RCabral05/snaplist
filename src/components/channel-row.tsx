import { Pressable, StyleSheet, Text, View } from "react-native";

import type { ChannelListing, MarketplaceAdapter, PublishState } from "@/lib/marketplaces";
import { colors, radius, spacing, type } from "@/theme";

const stateColor: Record<PublishState, string> = {
  draft: colors.draft,
  pending: colors.pending,
  live: colors.live,
  failed: colors.failed,
  ended: colors.inkFaint,
};

/**
 * One channel, in the two places channels appear: the picker on a draft (with a
 * checkbox) and the status list on a published listing (with a state dot).
 */
export function ChannelRow({
  adapter,
  selected,
  connected,
  status,
  issue,
  onPress,
}: {
  adapter: MarketplaceAdapter;
  selected?: boolean;
  connected?: boolean;
  status?: ChannelListing;
  issue?: string;
  onPress?: () => void;
}) {
  const needsConnection = adapter.requiresConnection && !connected;

  return (
    <Pressable
      onPress={onPress}
      disabled={!onPress}
      style={({ pressed }) => [s.row, selected && s.rowOn, pressed && onPress ? s.pressed : null]}
    >
      <View style={s.left}>
        <Text style={s.name}>{adapter.name}</Text>
        <Text style={s.blurb} numberOfLines={1}>
          {issue ?? (needsConnection ? "Not connected" : adapter.blurb)}
        </Text>
      </View>

      {status ? (
        <View style={s.status}>
          <View style={[s.dot, { backgroundColor: stateColor[status.state] }]} />
          <Text style={s.statusText}>{status.state}</Text>
        </View>
      ) : onPress ? (
        <View style={[s.check, selected && s.checkOn]}>
          {selected ? <Text style={s.tick}>OK</Text> : null}
        </View>
      ) : null}
    </Pressable>
  );
}

const s = StyleSheet.create({
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.paper,
  },
  rowOn: { borderColor: colors.ember, backgroundColor: "#fff7f3" },
  pressed: { opacity: 0.7 },
  left: { flex: 1, gap: 2 },
  name: { ...type.bodyMedium, color: colors.ink },
  blurb: { ...type.small, color: colors.textMuted },
  status: { flexDirection: "row", alignItems: "center", gap: spacing.xs },
  dot: { width: 8, height: 8, borderRadius: 4 },
  statusText: { ...type.label, color: colors.textMuted },
  check: {
    width: 26,
    height: 26,
    borderRadius: 13,
    borderWidth: 1.5,
    borderColor: colors.ruleStrong,
    alignItems: "center",
    justifyContent: "center",
  },
  checkOn: { backgroundColor: colors.ember, borderColor: colors.ember },
  tick: { ...type.label, fontSize: 9, color: colors.white },
});
