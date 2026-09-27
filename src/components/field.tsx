import type { ReactNode } from "react";
import { StyleSheet, Text, View } from "react-native";

import { colors, radius, spacing, type } from "@/theme";

/**
 * A filled well rather than an outlined box. On dark, a 1px border reads as a
 * seam; a lighter block reads as somewhere to type.
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
    backgroundColor: colors.raised,
  },
  hint: { ...type.small, fontSize: 13, color: colors.inkDim, paddingHorizontal: spacing.xs },
});
