import { useLocalSearchParams, useRouter } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Avatar } from "@/components/avatar";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { ShopGrid } from "@/components/shop-grid";
import { useGoBack } from "@/lib/navigation";
import { useBrandShop } from "@/lib/shop";
import { colors, spacing, type } from "@/theme";

/**
 * A brand's storefront.
 *
 * Set like the cover of a catalogue: the logo, the name large in serif, the bio,
 * then a rule with the count sitting in it before the goods begin. This is the
 * page the whole brand model exists for - products hang off it now and events
 * will hang off the same row later - so it should read as somewhere, not as a
 * filter applied to Shop.
 */
export default function BrandScreen() {
  const { slug } = useLocalSearchParams<{ slug: string }>();
  const router = useRouter();
  const { brand, items, isLoading, refresh } = useBrandShop(slug);
  const goBack = useGoBack("/");

  const count = items.length === 1 ? "1 listing" : `${items.length} listings`;

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.nav}>
        <Pressable onPress={goBack} hitSlop={14}>
          <Icon name="chevron.left" size={18} color={colors.ink} weight="semibold" />
        </Pressable>
      </View>

      <ShopGrid
        items={items}
        showBrand={false}
        onRefresh={refresh}
        refreshing={isLoading && items.length > 0}
        header={
          <View style={s.cover}>
            <Avatar url={brand?.logo_url} name={brand?.name} handle={slug} size={76} />
            <Text style={s.name}>{brand?.name || `@${slug}`}</Text>
            <Text style={s.handle}>@{brand?.slug ?? slug}</Text>
            {brand?.bio ? <Text style={s.bio}>{brand.bio}</Text> : null}

            {!isLoading && brand ? (
              <View style={s.rule}>
                <View style={s.line} />
                <Text style={s.count}>{count}</Text>
                <View style={s.line} />
              </View>
            ) : null}
          </View>
        }
        empty={
          isLoading ? undefined : (
            <EmptyState
              icon={brand ? "bag" : "questionmark.circle"}
              title={brand ? "Nothing for sale yet" : "No such brand"}
              body={
                brand
                  ? "This brand has not published anything."
                  : `No brand on Snaplist goes by @${slug}.`
              }
              actionLabel={brand ? undefined : "Back to Shop"}
              onAction={brand ? undefined : () => router.replace("/")}
            />
          )
        }
      />
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  nav: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.sm },

  cover: { alignItems: "center", paddingBottom: spacing.lg, gap: spacing.xs },
  name: { ...type.display, color: colors.ink, textAlign: "center", marginTop: spacing.md },
  handle: { ...type.label, color: colors.ember },
  bio: {
    ...type.small,
    fontSize: 15,
    color: colors.textMuted,
    textAlign: "center",
    lineHeight: 22,
    maxWidth: 300,
    marginTop: spacing.xs,
  },

  // A rule with the count sitting in it, the way a catalogue breaks a section.
  rule: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    alignSelf: "stretch",
    marginTop: spacing.lg,
  },
  line: { flex: 1, height: StyleSheet.hairlineWidth, backgroundColor: colors.ruleStrong },
  count: { ...type.label, fontSize: 9, color: colors.inkFaint },
});
