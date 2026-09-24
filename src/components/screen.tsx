import type { ReactNode } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { colors, spacing, type } from "@/theme";

/**
 * The frame every tab sits in: safe area, one large title, then content.
 *
 * It exists so the four tabs cannot drift apart. Before this, each screen
 * repeated its own header block and they had already diverged by a few points
 * of padding, which reads as sloppiness rather than as four separate screens.
 */
export function Screen({
  title,
  action,
  scroll = false,
  children,
}: {
  title: string;
  /** Rendered at the trailing edge of the title row. */
  action?: ReactNode;
  scroll?: boolean;
  children: ReactNode;
}) {
  const body = scroll ? (
    <ScrollView
      contentContainerStyle={s.scrollBody}
      showsVerticalScrollIndicator={false}
      keyboardShouldPersistTaps="handled"
    >
      {children}
    </ScrollView>
  ) : (
    <View style={s.flex}>{children}</View>
  );

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.header}>
        <Text style={s.title} numberOfLines={1}>
          {title}
        </Text>
        {action}
      </View>
      {body}
    </SafeAreaView>
  );
}

/** A quiet run-in heading for a group of rows. */
export function SectionLabel({ children, style }: { children: ReactNode; style?: object }) {
  return <Text style={[s.section, style]}>{children}</Text>;
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  flex: { flex: 1 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.md,
  },
  title: { ...type.display, color: colors.ink, flexShrink: 1 },
  scrollBody: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl, gap: spacing.md },
  section: { ...type.label, color: colors.textFaint },
});
