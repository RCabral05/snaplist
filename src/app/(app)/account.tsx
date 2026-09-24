import { useRouter } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";

import { Avatar } from "@/components/avatar";
import { Icon } from "@/components/icon";
import { Screen, SectionLabel } from "@/components/screen";
import { useAuth } from "@/lib/auth";
import { useBrands, type Brand } from "@/lib/brands";
import { colors, radius, spacing, type } from "@/theme";

export default function AccountScreen() {
  const router = useRouter();
  const { user, profile, signOut } = useAuth();
  const { brands, active, setActive } = useBrands();


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

      {/* Channels used to live here. They belong to a brand, not to an account -
          @nike's eBay is not another brand's - so they are on the Brand tab. */}

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


  signOut: { alignItems: "center", paddingVertical: spacing.md, marginTop: spacing.sm },
  signOutText: { ...type.body, color: colors.danger },
});
