import { Stack } from "expo-router";

import { colors } from "@/theme";

/**
 * Home and profile are separate screens now, so this group needs its own stack:
 * profile is pushed over home rather than being home.
 */
export default function AppLayout() {
  return (
    <Stack
      screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.void } }}
    />
  );
}
