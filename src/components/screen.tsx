import type { ReactNode } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { colors, spacing, type } from "@/theme";

/**
 * The frame every tab sits in.
 *
 * The title is a serif hero, set large and close to the top-left with nothing
 * beside it. That is the whole editorial move: one confident word, a lot of air,
 * and then the goods. A centred title with icons either side would make this
 * look like software; this should look like a shop.
 */
export function Screen({
  title,
  eyebrow,
  action,
  scroll = false,
  children,
}: {
  title: string;
  /** Small caps line above the title, when the screen needs context. */
  eyebrow?: string;
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
        <View style={s.headerText}>
          {eyebrow ? <Text style={s.eyebrow}>{eyebrow}</Text> : null}
          <Text style={s.title} numberOfLines={1}>
            {title}
          </Text>
        </View>
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
    alignItems: "flex-end",
    justifyContent: "space-between",
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
    paddingBottom: spacing.md,
  },
  headerText: { flexShrink: 1, gap: 2 },
  eyebrow: { ...type.label, color: colors.inkFaint },
  title: { ...type.hero, color: colors.ink },
  scrollBody: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl, gap: spacing.md },
  section: { ...type.label, color: colors.inkFaint },
});
