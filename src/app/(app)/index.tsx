import { SafeAreaView } from "react-native-safe-area-context";
import { StyleSheet, Text, View } from "react-native";

import { MOCK } from "@/lib/api";
import { colors, spacing, type } from "@/theme";

/**
 * The buyer side of our own marketplace. It has nothing to show until the backend
 * serves a feed, and saying so beats a grid of placeholder rectangles.
 */
export default function ShopScreen() {
  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.header}>
        <Text style={s.title}>Shop</Text>
      </View>
      <View style={s.empty}>
        <Text style={s.emptyTitle}>Nothing listed yet</Text>
        <Text style={s.emptyBody}>
          {MOCK
            ? "The marketplace feed comes from the backend, which is not wired up yet. Set EXPO_PUBLIC_API_URL to point at it."
            : "Be the first to list something."}
        </Text>
      </View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  header: { paddingHorizontal: spacing.md, paddingVertical: spacing.md },
  title: { ...type.display, color: colors.ink },
  empty: { flex: 1, alignItems: "center", justifyContent: "center", padding: spacing.xl, gap: spacing.sm },
  emptyTitle: { ...type.title, color: colors.ink },
  emptyBody: { ...type.body, color: colors.textMuted, textAlign: "center" },
});
