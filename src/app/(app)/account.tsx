import { useRouter } from "expo-router";
import { Alert, Pressable, StyleSheet, Text, View } from "react-native";

import { Avatar } from "@/components/avatar";
import { Icon } from "@/components/icon";
import { Screen, SectionLabel } from "@/components/screen";
import { useAuth } from "@/lib/auth";
import { useBrands, type Brand } from "@/lib/brands";
import { useConnections } from "@/lib/connections";
import { adapters, type MarketplaceAdapter } from "@/lib/marketplaces";
import { colors, fonts, radius, spacing, type } from "@/theme";

export default function AccountScreen() {
  const router = useRouter();
  const { user, profile, signOut } = useAuth();
  const { brands, active, setActive } = useBrands();
  const { isConnected, disconnect } = useConnections();

  return (
    <Screen title="Account" scroll>
      {/* The brand comes first: it is what the seller is operating as, and every
          other tab is scoped to whichever one is active here. */}
      <View style={s.group}>
        <SectionLabel>{brands.length > 1 ? "Selling as" : "Your brand"}</SectionLabel>
        <View style={s.rows}>
          {brands.map((brand, i) => (
            <BrandRow
              key={brand.id}
              brand={brand}
              isActive={brand.id === active?.id}
              only={brands.length === 1}
              first={i === 0}
              onSelect={() => setActive(brand.id)}
              onSettings={() => {
                setActive(brand.id);
                router.push("/brand-settings");
              }}
            />
          ))}
          <Pressable
            onPress={() => router.push("/new-brand")}
            style={({ pressed }) => [s.row, s.rowDivided, pressed && s.pressed]}
          >
            <Icon name="plus.circle" size={22} color={colors.ember} />
            <Text style={s.addText}>Add a brand</Text>
          </Pressable>
        </View>
      </View>

      <View style={s.group}>
        <SectionLabel>You</SectionLabel>
        <Pressable
          onPress={() => router.push("/edit-profile")}
          style={({ pressed }) => [s.profile, pressed && s.pressed]}
        >
          <Avatar url={profile?.avatar_url} name={profile?.display_name} size={44} />
          <View style={s.who}>
            <Text style={s.name} numberOfLines={1}>
              {profile?.display_name || "Add your name"}
            </Text>
            <Text style={s.email} numberOfLines={1}>
              {user?.email ?? ""}
            </Text>
          </View>
          <Icon name="chevron.right" size={14} color={colors.inkFaint} weight="semibold" />
        </Pressable>
      </View>

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
 * Tapping the row switches to that brand; the chevron opens its settings. With
 * only one brand there is nothing to switch to, so the whole row just opens
 * settings and no tick is drawn.
 */
function BrandRow({
  brand,
  isActive,
  only,
  first,
  onSelect,
  onSettings,
}: {
  brand: Brand;
  isActive: boolean;
  only: boolean;
  first: boolean;
  onSelect: () => void;
  onSettings: () => void;
}) {
  return (
    <Pressable
      onPress={only ? onSettings : onSelect}
      style={({ pressed }) => [s.row, !first && s.rowDivided, pressed && s.pressed]}
    >
      <Avatar url={brand.logo_url} name={brand.name} handle={brand.slug} size={36} />
      <View style={s.rowBody}>
        <Text style={s.rowName} numberOfLines={1}>
          {brand.name || `@${brand.slug}`}
        </Text>
        <Text style={s.rowBlurb} numberOfLines={1}>
          @{brand.slug}
        </Text>
      </View>

      {!only && isActive ? (
        <Icon name="checkmark" size={14} color={colors.ember} weight="bold" />
      ) : null}
      <Pressable onPress={onSettings} hitSlop={10}>
        <Icon name="chevron.right" size={14} color={colors.inkFaint} weight="semibold" />
      </Pressable>
    </Pressable>
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

  group: { gap: spacing.sm },
  profile: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.paper,
  },
  who: { flex: 1, minWidth: 0, gap: 2 },
  name: { ...type.bodyMedium, fontSize: 15, color: colors.ink },
  email: { ...type.small, fontSize: 13, color: colors.textMuted },

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
  addText: { ...type.bodyMedium, fontSize: 15, color: colors.ember, flex: 1 },

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
