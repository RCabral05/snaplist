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

/**
 * Primary is near-white on near-black. On a dark ground the brightest thing is
 * the most important thing, and spending the accent on a button would leave
 * nothing to spend it on anywhere else.
 */
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
        <ActivityIndicator color={variant === "primary" ? colors.void : colors.ink} />
      ) : (
        <Text style={[s.label, variant === "primary" ? s.labelPrimary : s.labelDefault]}>
          {label}
        </Text>
      )}
    </Pressable>
  );
}

const s = StyleSheet.create({
  base: {
    minHeight: 54,
    borderRadius: radius.md,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: spacing.xl,
  },
  primary: { backgroundColor: colors.ink },
  secondary: { backgroundColor: colors.raisedHigh },
  ghost: { backgroundColor: "transparent" },
  pressed: { opacity: 0.7 },
  off: { opacity: 0.3 },
  label: { fontFamily: fonts.sansMedium, fontSize: 16, letterSpacing: -0.2 },
  labelPrimary: { color: colors.void },
  labelDefault: { color: colors.ink },
});
