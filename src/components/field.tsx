import type { ReactNode } from "react";
import { StyleSheet, Text, View } from "react-native";

import { colors, radius, spacing, type } from "@/theme";

/**
 * Label, a bordered control, and a line of help underneath. The control is a
 * child rather than a prop because the two fields that use this are not the same
 * shape - one is a plain input, the other carries an "@" and a spinner.
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
  wrap: { gap: spacing.xs },
  label: { ...type.label, color: colors.textMuted },
  control: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.paper,
  },
  hint: { ...type.small, color: colors.textMuted, paddingHorizontal: 2 },
});
