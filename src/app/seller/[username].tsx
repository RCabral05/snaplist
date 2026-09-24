import { useLocalSearchParams, useRouter } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Avatar } from "@/components/avatar";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { ShopGrid } from "@/components/shop-grid";
import { useSellerShop } from "@/lib/shop";
import { colors, spacing, type } from "@/theme";

/**
 * One seller's shop.
 *
 * Snaplist has a single storefront per seller and the profile is that storefront,
 * so this is the brand page: everything they have published, under their handle.
 * It reads public_profiles rather than profiles - the view exists precisely so a
 * buyer can see a handle and an avatar without the whole row being readable.
 */
export default function SellerShopScreen() {
  const { username } = useLocalSearchParams<{ username: string }>();
  const router = useRouter();
  const { seller, items, isLoading, refresh } = useSellerShop(username);

  const plural = items.length === 1 ? "1 listing" : `${items.length} listings`;

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.nav}>
        <Pressable onPress={() => router.back()} hitSlop={12}>
          <Icon name="chevron.left" size={18} color={colors.ink} weight="semibold" />
        </Pressable>
      </View>

      <ShopGrid
        items={items}
        showSeller={false}
        onRefresh={refresh}
        refreshing={isLoading && items.length > 0}
        header={
          <View style={s.header}>
            <Avatar
              url={seller?.avatar_url}
              name={seller?.display_name}
              handle={username}
              size={64}
            />
            <View style={s.who}>
              <Text style={s.name} numberOfLines={1}>
                {seller?.display_name || `@${username}`}
              </Text>
              <Text style={s.handle} numberOfLines={1}>
                @{seller?.username ?? username}
              </Text>
              {!isLoading && seller ? <Text style={s.count}>{plural}</Text> : null}
            </View>
          </View>
        }
        empty={
          isLoading ? undefined : (
            <EmptyState
              icon={seller ? "bag" : "questionmark.circle"}
              title={seller ? "Nothing for sale yet" : "No such seller"}
              body={
                seller
                  ? "This seller has not published anything."
                  : `Nobody on Snaplist goes by @${username}.`
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
  header: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingBottom: spacing.lg,
  },
  who: { flex: 1, minWidth: 0, gap: 2 },
  name: { ...type.title, color: colors.ink },
  handle: { ...type.body, color: colors.ember },
  count: { ...type.small, fontSize: 13, color: colors.textMuted, marginTop: 2 },
});
