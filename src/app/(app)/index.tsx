import { useRouter } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Avatar } from "@/components/avatar";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import { useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

/**
 * Home. Signing in lands here, and here is the profile.
 *
 * There is one screen behind the door on purpose, so no tab bar - a bar with a
 * single destination is a bar telling you there is nowhere to go.
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

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.top}>
        <Text style={s.mark}>Snaplist</Text>
        <Pressable onPress={() => signOut().catch(() => {})} hitSlop={10}>
          <Text style={s.signOut}>Sign out</Text>
        </Pressable>
      </View>

      <View style={s.body}>
        <Avatar url={profile?.avatar_url} name={name} size={104} />

        <View style={s.who}>
          <Text style={s.name}>{name || "Add your name"}</Text>
          <Text style={s.email}>{user?.email ?? ""}</Text>
        </View>

        {joined ? (
          <View style={s.rule}>
            <View style={s.line} />
            <Text style={s.since}>Member since {joined}</Text>
            <View style={s.line} />
          </View>
        ) : null}

        <Button
          label="Edit profile"
          onPress={() => router.push("/edit-profile")}
          style={s.edit}
        />
      </View>

      <Pressable
        onPress={() => router.push("/edit-profile")}
        style={({ pressed }) => [s.hint, pressed && s.pressed]}
      >
        <Icon name="person.crop.circle" size={14} color={colors.inkFaint} />
        <Text style={s.hintText}>
          {name && profile?.avatar_url ? "Your profile is set up." : "Finish setting up your profile."}
        </Text>
      </Pressable>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  top: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
  },
  mark: { ...type.label, color: colors.ember },
  signOut: { ...type.small, fontSize: 13, color: colors.inkFaint },

  body: { flex: 1, alignItems: "center", justifyContent: "center", gap: spacing.md, paddingHorizontal: spacing.lg },
  who: { alignItems: "center", gap: 2 },
  name: { ...type.display, color: colors.ink, textAlign: "center" },
  email: { ...type.small, fontSize: 15, color: colors.textMuted },

  rule: { flexDirection: "row", alignItems: "center", gap: spacing.md, alignSelf: "stretch" },
  line: { flex: 1, height: StyleSheet.hairlineWidth, backgroundColor: colors.ruleStrong },
  since: { ...type.label, fontSize: 9, color: colors.inkFaint },

  edit: { marginTop: spacing.sm, minWidth: 220 },

  hint: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: spacing.sm,
    paddingVertical: spacing.md,
    marginHorizontal: spacing.lg,
    marginBottom: spacing.md,
    borderRadius: radius.md,
    backgroundColor: colors.paperAlt,
  },
  pressed: { opacity: 0.7 },
  hintText: { ...type.small, fontSize: 13, color: colors.inkDim },
});
