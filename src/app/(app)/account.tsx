import { useRouter } from "expo-router";
import { Alert, Pressable, StyleSheet, Text, View } from "react-native";

import { Avatar } from "@/components/avatar";
import { Icon } from "@/components/icon";
import { Screen, SectionLabel } from "@/components/screen";
import { useAuth } from "@/lib/auth";
import { useConnections } from "@/lib/connections";
import { adapters, type MarketplaceAdapter } from "@/lib/marketplaces";
import { colors, fonts, radius, spacing, type } from "@/theme";

export default function AccountScreen() {
  const router = useRouter();
  const { user, profile, signOut } = useAuth();
  const { isConnected, disconnect } = useConnections();

  return (
    <Screen title="Account" scroll>
      {/* The whole card is the target, not a small "edit" link: this is the only
          way into the profile editor, and a 56pt row is far easier to hit. */}
      <Pressable
        onPress={() => router.push("/edit-profile")}
        style={({ pressed }) => [s.profile, pressed && s.pressed]}
      >
        <Avatar
          url={profile?.avatar_url}
          name={profile?.display_name}
          handle={profile?.username}
          size={56}
        />
        <View style={s.who}>
          <Text style={s.name} numberOfLines={1}>
            {profile?.display_name || "Add your name"}
          </Text>
          {profile?.username ? (
            <Text style={s.handle} numberOfLines={1}>
              @{profile.username}
            </Text>
          ) : null}
          <Text style={s.email} numberOfLines={1}>
            {user?.email ?? ""}
          </Text>
        </View>
        <Icon name="chevron.right" size={14} color={colors.inkFaint} weight="semibold" />
      </Pressable>

      <View style={s.group}>
        <SectionLabel>Channels</SectionLabel>
        <View style={s.rows}>
          {adapters.map((adapter, i) => (
            <ChannelConnection
              key={adapter.id}
              adapter={adapter}
              connected={isConnected(adapter.id)}
              first={i === 0}
              onDisconnect={() =>
                disconnect(adapter.id).catch((e) =>
                  Alert.alert("Could not disconnect", e?.message ?? ""),
                )
              }
            />
          ))}
        </View>
      </View>

      <Pressable
        onPress={() => signOut().catch(() => {})}
        style={({ pressed }) => [s.signOut, pressed && s.pressed]}
      >
        <Text style={s.signOutText}>Sign out</Text>
      </Pressable>
    </Screen>
  );
}

/**
 * One channel and its single action. The action is a pill on the row rather than
 * a full-width button beneath it - stacking two 52pt buttons down the screen made
 * connecting eBay look like the most important thing in the app.
 */
function ChannelConnection({
  adapter,
  connected,
  first,
  onDisconnect,
}: {
  adapter: MarketplaceAdapter;
  connected: boolean;
  first: boolean;
  onDisconnect: () => void;
}) {
  const press = () => {
    if (connected) return onDisconnect();
    // Connecting is an OAuth round trip that finishes on the backend, because
    // that is the only place the token may land.
    Alert.alert(
      "Not available yet",
      "Connecting " +
        adapter.name +
        " needs the backend to complete the OAuth handshake and store the token. Nothing to connect to yet.",
    );
  };

  return (
    <View style={[s.row, !first && s.rowDivided]}>
      <View style={s.rowBody}>
        <Text style={s.rowName}>{adapter.name}</Text>
        <Text style={s.rowBlurb} numberOfLines={1}>
          {adapter.requiresConnection
            ? connected
              ? "Connected"
              : "Not connected"
            : adapter.blurb}
        </Text>
      </View>

      {adapter.requiresConnection ? (
        <Pressable onPress={press} style={({ pressed }) => [s.pill, pressed && s.pressed]}>
          <Text style={[s.pillText, connected && s.pillTextOff]}>
            {connected ? "Disconnect" : "Connect"}
          </Text>
        </Pressable>
      ) : (
        <View style={s.always}>
          <Icon name="checkmark" size={12} color={colors.live} weight="bold" />
          <Text style={s.alwaysText}>Always on</Text>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  pressed: { opacity: 0.6 },

  profile: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radius.lg,
    backgroundColor: colors.surface,
  },
  who: { flex: 1, minWidth: 0, gap: 2 },
  name: { ...type.bodyMedium, color: colors.ink },
  handle: { ...type.small, fontSize: 13, color: colors.ember },
  email: { ...type.small, fontSize: 13, color: colors.textMuted },

  group: { gap: spacing.sm, marginTop: spacing.sm },
  rows: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    backgroundColor: colors.paper,
    overflow: "hidden",
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
  },
  rowDivided: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border },
  rowBody: { flex: 1, minWidth: 0, gap: 2 },
  rowName: { ...type.bodyMedium, fontSize: 15, color: colors.ink },
  rowBlurb: { ...type.small, fontSize: 13, color: colors.textMuted },

  pill: {
    paddingHorizontal: spacing.md,
    paddingVertical: 7,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.borderStrong,
  },
  pillText: { ...type.small, fontFamily: fonts.sansMedium, fontSize: 13, color: colors.ink },
  pillTextOff: { color: colors.textMuted },
  always: { flexDirection: "row", alignItems: "center", gap: spacing.xs },
  alwaysText: { ...type.small, fontSize: 13, color: colors.live },

  signOut: { alignItems: "center", paddingVertical: spacing.md, marginTop: spacing.sm },
  signOutText: { ...type.body, color: colors.danger },
});
