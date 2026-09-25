import { Image } from "expo-image";
import { useRouter } from "expo-router";
import type { ReactElement } from "react";
import { FlatList, Pressable, StyleSheet, Text, View } from "react-native";

import { money } from "@/lib/listings";
import { usePhotoUrl } from "@/lib/photos";
import type { ShopItem } from "@/lib/shop";
import { colors, radius, spacing, type } from "@/theme";

import { Icon } from "./icon";

/**
 * Two columns of goods.
 *
 * Cards have no border, no fill and no shadow - the photograph is the card, and
 * a frame around a photograph on warm paper only ever makes it look smaller. The
 * text below is a caption: brand in small caps, then the thing, then the price
 * in serif, which is the line a buyer is actually scanning for.
 *
 * Portrait rather than square. Clothes, shoes and furniture are taller than they
 * are wide, and a square crop cuts the top off most of them.
 */
export function ShopGrid({
  items,
  header,
  empty,
  showBrand = true,
  onRefresh,
  refreshing,
}: {
  items: ShopItem[];
  header?: ReactElement;
  empty?: ReactElement;
  showBrand?: boolean;
  onRefresh?: () => void;
  refreshing?: boolean;
}) {
  return (
    <FlatList
      data={items}
      keyExtractor={(i) => i.id}
      renderItem={({ item }) => <Card item={item} showBrand={showBrand} />}
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

function Card({ item, showBrand }: { item: ShopItem; showBrand: boolean }) {
  const router = useRouter();
  const url = usePhotoUrl(item.photo);
  const slug = item.brand?.slug;

  return (
    <Pressable
      onPress={() => router.push({ pathname: "/item/[id]", params: { id: item.id } })}
      style={({ pressed }) => [s.card, pressed && s.pressed]}
    >
      <View style={s.frame}>
        {url ? (
          <Image source={{ uri: url }} style={s.photo} contentFit="cover" transition={160} />
        ) : (
          <View style={s.photoEmpty}>
            <Icon name="photo" size={20} color={colors.ruleStrong} weight="light" />
          </View>
        )}
      </View>

      {showBrand && (item.brand?.name || slug) ? (
        <Text style={s.brand} numberOfLines={1}>
          {item.brand?.name || slug}
        </Text>
      ) : null}
      <Text style={s.title} numberOfLines={1}>
        {item.title || "Untitled item"}
      </Text>
      <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  list: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl, gap: spacing.xl },
  listEmpty: { flexGrow: 1 },
  column: { gap: spacing.md },
  card: { flex: 1, gap: 2 },
  pressed: { opacity: 0.72 },
  frame: {
    width: "100%",
    aspectRatio: 4 / 5,
    borderRadius: radius.md,
    overflow: "hidden",
    backgroundColor: colors.paperAlt,
    marginBottom: spacing.sm,
  },
  photo: { width: "100%", height: "100%" },
  photoEmpty: { flex: 1, alignItems: "center", justifyContent: "center" },
  brand: { ...type.label, fontSize: 9, color: colors.inkFaint },
  title: { ...type.small, fontSize: 13, color: colors.inkDim },
  price: { ...type.price, fontSize: 19, color: colors.ink, marginTop: 1 },
});
