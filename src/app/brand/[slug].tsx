import { useLocalSearchParams } from "expo-router";
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
 * A brand's storefront: its logo, its handle, and everything it has published.
 * This is the page the whole brand model exists for - products hang off it now,
 * and events will hang off the same row later.
 */
export default function BrandScreen() {
  const { slug } = useLocalSearchParams<{ slug: string }>();
  const { brand, items, isLoading, refresh } = useBrandShop(slug);
  const goBack = useGoBack("/");

  const count = items.length === 1 ? "1 listing" : `${items.length} listings`;

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.nav}>
        <Pressable onPress={goBack} hitSlop={12}>
          <Icon name="chevron.left" size={18} color={colors.ink} weight="semibold" />
        </Pressable>
      </View>

      <ShopGrid
        items={items}
        showBrand={false}
        onRefresh={refresh}
        refreshing={isLoading && items.length > 0}
        header={
          <View style={s.header}>
            <View style={s.identity}>
              <Avatar url={brand?.logo_url} name={brand?.name} handle={slug} size={64} />
              <View style={s.who}>
                <Text style={s.name} numberOfLines={1}>
                  {brand?.name || `@${slug}`}
                </Text>
                <Text style={s.handle} numberOfLines={1}>
                  @{brand?.slug ?? slug}
                </Text>
                {!isLoading && brand ? <Text style={s.count}>{count}</Text> : null}
              </View>
            </View>
            {brand?.bio ? <Text style={s.bio}>{brand.bio}</Text> : null}
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
            />
          )
        }
      />
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  nav: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.xs },
  header: { paddingBottom: spacing.lg, gap: spacing.md },
  identity: { flexDirection: "row", alignItems: "center", gap: spacing.md },
  who: { flex: 1, minWidth: 0, gap: 2 },
  name: { ...type.title, color: colors.ink },
  handle: { ...type.body, color: colors.ember },
  count: { ...type.small, fontSize: 13, color: colors.textMuted, marginTop: 2 },
  bio: { ...type.small, color: colors.textMuted, lineHeight: 20 },
});
