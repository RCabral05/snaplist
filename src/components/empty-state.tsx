import type { SFSymbol } from "expo-symbols";
import { StyleSheet, Text, View } from "react-native";

import { colors, spacing, type } from "@/theme";

import { Button } from "./button";
import { Icon } from "./icon";

/**
 * What a screen shows instead of nothing. The glyph is small and faint and the
 * sentence is serif - an empty shelf should look like a quiet shop, not an error
 * dialog, which is what a big centred icon and a grey box always look like.
 */
export function EmptyState({
  icon,
  title,
  body,
  actionLabel,
  onAction,
}: {
  icon: SFSymbol;
  title: string;
  body?: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <View style={s.wrap}>
      <Icon name={icon} size={24} color={colors.ruleStrong} weight="light" />
      <Text style={s.title}>{title}</Text>
      {body ? <Text style={s.body}>{body}</Text> : null}
      {actionLabel && onAction ? (
        <Button label={actionLabel} onPress={onAction} style={s.action} />
      ) : null}
    </View>
  );
}

const s = StyleSheet.create({
  wrap: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.sm,
  },
  title: { ...type.title, color: colors.ink, textAlign: "center", marginTop: spacing.sm },
  body: {
    ...type.small,
    fontSize: 15,
    color: colors.textMuted,
    textAlign: "center",
    lineHeight: 22,
    maxWidth: 300,
  },
  action: { marginTop: spacing.md, alignSelf: "center", minWidth: 200 },
});
