import type { SFSymbol } from "expo-symbols";
import { StyleSheet, Text, View } from "react-native";

import { colors, radius, spacing, type } from "@/theme";

import { Button } from "./button";
import { Icon } from "./icon";

/**
 * What a screen shows instead of nothing.
 *
 * The body line is capped in width on purpose: centred text that runs the full
 * width of a phone is hard to read and looks like an error message. A soft disc
 * behind the glyph gives the block something to sit on so it does not read as
 * text stranded in white space.
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
      <View style={s.disc}>
        <Icon name={icon} size={30} color={colors.inkFaint} weight="light" />
      </View>
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
  disc: {
    width: 64,
    height: 64,
    borderRadius: radius.pill,
    backgroundColor: colors.surface,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: spacing.xs,
  },
  title: { ...type.heading, fontSize: 18, color: colors.ink, textAlign: "center" },
  body: {
    ...type.small,
    color: colors.textMuted,
    textAlign: "center",
    lineHeight: 20,
    maxWidth: 260,
  },
  // alignSelf must not be "stretch" here: it overrides the parent alignItems and
  // pins the button to the leading edge, where maxWidth then makes it look
  // deliberately left-aligned rather than centred.
  action: { marginTop: spacing.md, alignSelf: "center", minWidth: 200 },
});
