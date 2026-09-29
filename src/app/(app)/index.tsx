import { useRouter } from "expo-router";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { AppMenu } from "@/components/app-menu";
import { Icon } from "@/components/icon";
import { useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

/**
 * Home.
 *
 * The profile used to be this screen; it has moved behind the menu, which
 * leaves home free for whatever the app turns out to be. Until that is decided
 * the only honest things to put here are who you are, what is still missing
 * from your account, and a placeholder that admits to being one - a fake chart
 * or a row of dummy cards would only make the screen harder to replace.
 */
export default function HomeScreen() {
  const router = useRouter();
  const { profile } = useAuth();

  const name = profile?.display_name?.trim();
  const first = name ? name.split(/\s+/)[0] : null;

  const now = new Date();
  const hour = now.getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  const today = now.toLocaleDateString(undefined, {
    weekday: "long",
    day: "numeric",
    month: "long",
  });

  const missing = !name
    ? { text: "Add your name", hint: "Your profile has no name on it yet." }
    : !profile?.username
      ? { text: "Pick a username", hint: "Claim your handle before someone else does." }
      : !profile?.avatar_url
        ? { text: "Add a photo", hint: "One picture and your profile is done." }
        : null;

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.bar}>
        <AppMenu />
        <Text style={s.mark}>Snaplist</Text>
      </View>

      <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false}>
        <View style={s.hello}>
          <Text style={s.day}>{today}</Text>
          <Text style={s.greeting}>
            {greeting}
            {first ? "," : "."}
            {first ? `\n${first}.` : ""}
          </Text>
        </View>

        {missing ? (
          <Pressable
            style={({ pressed }) => [s.todo, pressed && s.todoPressed]}
            onPress={() => router.push("/edit-profile")}
          >
            <View style={s.todoIcon}>
              <Icon name="sparkles" size={15} color={colors.ember} />
            </View>
            <View style={s.todoText}>
              <Text style={s.todoTitle}>{missing.text}</Text>
              <Text style={s.todoHint}>{missing.hint}</Text>
            </View>
            <Icon name="chevron.right" size={14} color={colors.inkFaint} />
          </Pressable>
        ) : null}

        <View style={s.empty}>
          <Icon name="square.dashed" size={26} color={colors.inkFaint} />
          <Text style={s.emptyTitle}>Nothing here yet</Text>
          <Text style={s.emptyBody}>
            This is where the app goes. Your account, profile and photo are all set up and waiting
            underneath it.
          </Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.void },

  bar: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
    paddingBottom: spacing.md,
  },
  mark: { ...type.label, color: colors.ember },

  body: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.xxl,
    gap: spacing.lg,
  },

  hello: { gap: spacing.sm },
  day: { ...type.label, color: colors.inkFaint },
  greeting: { ...type.hero, color: colors.ink },

  todo: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radius.lg,
    backgroundColor: colors.raised,
  },
  todoPressed: { backgroundColor: colors.raisedHigh },
  todoIcon: {
    width: 34,
    height: 34,
    borderRadius: radius.pill,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: colors.emberSoft,
  },
  todoText: { flex: 1, gap: 2 },
  todoTitle: { ...type.bodyMedium, fontSize: 15, color: colors.ink },
  todoHint: { ...type.small, fontSize: 13, color: colors.inkFaint },

  empty: {
    alignItems: "center",
    gap: spacing.sm,
    paddingVertical: spacing.xl,
    paddingHorizontal: spacing.lg,
    borderRadius: radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.line,
  },
  emptyTitle: { ...type.heading, color: colors.inkDim, marginTop: spacing.xs },
  emptyBody: {
    ...type.small,
    fontSize: 13,
    color: colors.inkFaint,
    textAlign: "center",
    lineHeight: 19,
    maxWidth: 260,
  },
});
