import { Image } from "expo-image";
import { useRouter } from "expo-router";
import type { ReactElement } from "react";
import { FlatList, Pressable, StyleSheet, Text, View } from "react-native";

import { money } from "@/lib/listings";
import { usePhotoUrl } from "@/lib/photos";
import type { ShopItem } from "@/lib/shop";
import { colors, radius, spacing, type } from "@/theme";

import { Avatar } from "./avatar";
import { Icon } from "./icon";

/**
 * Two columns of product cards, used by the Shop feed and by one seller's shop.
 * The photo leads: these are second-hand goods and the picture is the listing.
 */
export function ShopGrid({
  items,
  header,
  empty,
  showSeller = true,
  onRefresh,
  refreshing,
}: {
  items: ShopItem[];
  header?: ReactElement;
  empty?: ReactElement;
  showSeller?: boolean;
  onRefresh?: () => void;
  refreshing?: boolean;
}) {
  return (
    <FlatList
      data={items}
      keyExtractor={(i) => i.id}
      renderItem={({ item }) => <Card item={item} showSeller={showSeller} />}
      numColumns={2}
      columnWrapperStyle={items.length ? s.column : undefined}
      contentContainerStyle={items.length ? s.list : s.listEmpty}
      ListHeaderComponent={header}
      ListEmptyComponent={empty}
      showsVerticalScrollIndicator={false}
      onRefresh={onRefresh}
      refreshing={!!refreshing}
    />
  );
}

function Card({ item, showSeller }: { item: ShopItem; showSeller: boolean }) {
  const router = useRouter();
  const url = usePhotoUrl(item.photo);
  const handle = item.seller?.username;

  return (
    <View style={s.card}>
      <View style={s.frame}>
        {url ? (
          <Image source={{ uri: url }} style={s.photo} contentFit="cover" transition={120} />
        ) : (
          <View style={s.photoEmpty}>
            <Icon name="photo" size={22} color={colors.inkFaint} weight="light" />
          </View>
        )}
      </View>

      <Text style={s.title} numberOfLines={1}>
        {item.title || "Untitled item"}
      </Text>
      <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>

      {showSeller && handle ? (
        <Pressable
          onPress={() => router.push({ pathname: "/seller/[username]", params: { username: handle } })}
          style={({ pressed }) => [s.seller, pressed && s.pressed]}
          hitSlop={6}
        >
          <Avatar
            url={item.seller?.avatar_url}
            name={item.seller?.display_name}
            handle={handle}
            size={18}
          />
          <Text style={s.handle} numberOfLines={1}>
            @{handle}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

const s = StyleSheet.create({
  list: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl, gap: spacing.lg },
  listEmpty: { flexGrow: 1 },
  column: { gap: spacing.md },
  card: { flex: 1, gap: 4 },
  frame: {
    width: "100%",
    aspectRatio: 1,
    borderRadius: radius.md,
    overflow: "hidden",
    backgroundColor: colors.surface,
  },
  photo: { width: "100%", height: "100%" },
  photoEmpty: { flex: 1, alignItems: "center", justifyContent: "center" },
  title: { ...type.small, color: colors.ink, marginTop: 2 },
  price: { ...type.price, fontSize: 15, color: colors.ink },
  seller: { flexDirection: "row", alignItems: "center", gap: 5, marginTop: 2 },
  pressed: { opacity: 0.6 },
  handle: { ...type.small, fontSize: 12, color: colors.textMuted, flexShrink: 1 },
});
