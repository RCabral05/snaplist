import { useRouter } from "expo-router";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Avatar } from "@/components/avatar";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import { useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

/**
 * Home, which is the profile.
 *
 * Left-aligned rather than centred. A centred avatar over a centred name is a
 * business card - fine for a thing you look at, wrong for a thing you use, and
 * it leaves the eye with nowhere to start. Everything hangs off one left edge,
 * and the facts sit in a list where they can be scanned instead of read.
 */
export default function HomeScreen() {
  const router = useRouter();
  const { user, profile, signOut } = useAuth();

  const name = profile?.display_name?.trim();
  const joined = profile?.created_at
    ? new Date(profile.created_at).toLocaleDateString(undefined, {
        month: "long",
        year: "numeric",
      })
    : null;

  const complete = !!name && !!profile?.username && !!profile?.avatar_url;

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.bar}>
        <Text style={s.mark}>Snaplist</Text>
        <Pressable onPress={() => signOut().catch(() => {})} hitSlop={12}>
          <Text style={s.signOut}>Sign out</Text>
        </Pressable>
      </View>

      <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false}>
        <Avatar url={profile?.avatar_url} name={name} handle={profile?.username} size={92} />

        <View style={s.who}>
          <Text style={s.name}>{name || "Add your name"}</Text>
          {profile?.username ? <Text style={s.handle}>@{profile.username}</Text> : null}
        </View>

        <View style={s.card}>
          <Row label="Email" value={user?.email ?? "—"} />
          <Row
            label="Username"
            value={profile?.username ? `@${profile.username}` : "Not set"}
            muted={!profile?.username}
          />
          {joined ? <Row label="Joined" value={joined} last /> : null}
        </View>

        <Button label="Edit profile" onPress={() => router.push("/edit-profile")} />

        {!complete ? (
          <View style={s.nudge}>
            <Icon name="sparkles" size={13} color={colors.ember} />
            <Text style={s.nudgeText}>
              {!profile?.username
                ? "Pick a username so people can find you."
                : !profile?.avatar_url
                  ? "Add a photo to finish your profile."
                  : "Add your name to finish your profile."}
            </Text>
          </View>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

function Row({
  label,
  value,
  muted,
  last,
}: {
  label: string;
  value: string;
  muted?: boolean;
  last?: boolean;
}) {
  return (
    <View style={[s.row, !last && s.rowDivided]}>
      <Text style={s.rowLabel}>{label}</Text>
      <Text style={[s.rowValue, muted && s.rowValueMuted]} numberOfLines={1}>
        {value}
      </Text>
    </View>
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
  signOut: { ...type.small, fontSize: 13, color: colors.inkFaint },

  body: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.xxl,
    gap: spacing.lg,
  },

  who: { gap: 4 },
  name: { ...type.hero, color: colors.ink },
  handle: { ...type.title, fontSize: 19, color: colors.ember },

  card: {
    borderRadius: radius.lg,
    backgroundColor: colors.raised,
    paddingHorizontal: spacing.md,
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: spacing.md,
    paddingVertical: spacing.md,
  },
  rowDivided: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.line },
  rowLabel: { ...type.label, color: colors.inkFaint },
  rowValue: { ...type.body, fontSize: 15, color: colors.ink, flexShrink: 1, textAlign: "right" },
  rowValueMuted: { color: colors.inkFaint },

  nudge: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
    borderRadius: radius.md,
    backgroundColor: colors.emberSoft,
  },
  nudgeText: { ...type.small, fontSize: 13, color: colors.inkDim, flex: 1, lineHeight: 19 },
});
