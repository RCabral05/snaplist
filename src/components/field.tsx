import type { ReactNode } from "react";
import { StyleSheet, Text, View } from "react-native";

import { colors, radius, spacing, type } from "@/theme";

/**
 * Label above, control below, help underneath. The control is filled rather than
 * outlined - on warm paper a box of rules reads as a form, a filled well reads as
 * somewhere to type.
 */
export function Field({
  label,
  hint,
  hintTone,
  children,
}: {
  label: string;
  hint?: string;
  hintTone?: string;
  children: ReactNode;
}) {
  return (
    <View style={s.wrap}>
      <Text style={s.label}>{label}</Text>
      <View style={s.control}>{children}</View>
      {hint ? <Text style={[s.hint, hintTone ? { color: hintTone } : null]}>{hint}</Text> : null}
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { gap: spacing.sm },
  label: { ...type.label, color: colors.inkFaint },
  control: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.paperAlt,
  },
  hint: { ...type.small, fontSize: 13, color: colors.textMuted, paddingHorizontal: spacing.xs },
});
