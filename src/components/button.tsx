import * as Haptics from "expo-haptics";
import { ActivityIndicator, Pressable, StyleSheet, Text, type ViewStyle } from "react-native";

import { colors, radius, spacing, type } from "@/theme";

type Props = {
  label: string;
  onPress: () => void;
  variant?: "primary" | "secondary" | "ghost";
  disabled?: boolean;
  loading?: boolean;
  style?: ViewStyle;
};

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
    minHeight: 52,
    borderRadius: radius.md,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: spacing.lg,
  },
  primary: { backgroundColor: colors.ember },
  secondary: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.border },
  ghost: { backgroundColor: "transparent" },
  pressed: { opacity: 0.8 },
  off: { opacity: 0.4 },
  label: { ...type.bodyMedium },
  labelPrimary: { color: colors.white },
  labelDark: { color: colors.ink },
});
