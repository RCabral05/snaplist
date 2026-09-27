import * as Haptics from "expo-haptics";
import { ActivityIndicator, Pressable, StyleSheet, Text, type ViewStyle } from "react-native";

import { colors, fonts, radius, spacing } from "@/theme";

type Props = {
  label: string;
  onPress: () => void;
  variant?: "primary" | "secondary" | "ghost";
  disabled?: boolean;
  loading?: boolean;
  style?: ViewStyle;
};

/** Pill-shaped and tall - an action should feel like a thing you press. */
export function Button({ label, onPress, variant = "primary", disabled, loading, style }: Props) {
  const isOff = disabled || loading;
  return (
    <Pressable
      accessibilityRole="button"
      disabled={isOff}
      onPress={() => {
        Haptics.selectionAsync();
        onPress();
      }}
      style={({ pressed }) => [
        s.base,
        variant === "primary" && s.primary,
        variant === "secondary" && s.secondary,
        variant === "ghost" && s.ghost,
        pressed && !isOff && s.pressed,
        isOff && s.off,
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={variant === "primary" ? colors.white : colors.ink} />
      ) : (
        <Text style={[s.label, variant === "primary" ? s.labelPrimary : s.labelDark]}>{label}</Text>
      )}
    </Pressable>
  );
}

const s = StyleSheet.create({
  base: {
    minHeight: 54,
    borderRadius: radius.pill,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: spacing.xl,
  },
  primary: { backgroundColor: colors.ink },
  secondary: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.ruleStrong },
  ghost: { backgroundColor: "transparent" },
  pressed: { opacity: 0.75 },
  off: { opacity: 0.35 },
  label: { fontFamily: fonts.sansMedium, fontSize: 16, letterSpacing: -0.1 },
  labelPrimary: { color: colors.white },
  labelDark: { color: colors.ink },
});
