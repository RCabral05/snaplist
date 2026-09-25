import { Image } from "expo-image";
import { useRouter } from "expo-router";
import { FlatList, Pressable, StyleSheet, Text, View } from "react-native";

import { money } from "@/lib/listings";
import { usePhotoUrl } from "@/lib/photos";
import type { ShopItem } from "@/lib/shop";
import { colors, fonts, radius, spacing, type } from "@/theme";

import { Avatar } from "./avatar";
import { Icon } from "./icon";

/**
 * Featured items, sideways. Bigger than a grid card and scrolled horizontally so
 * the row reads as a selection rather than as the top of the list - which is the
 * whole difference between "featured" and "newest".
 */
export function FeaturedRail({ items }: { items: ShopItem[] }) {
  if (!items.length) return null;

  return (
    <FlatList
      data={items}
      keyExtractor={(i) => i.id}
      renderItem={({ item }) => <Card item={item} />}
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={s.rail}
    />
  );
}

function Card({ item }: { item: ShopItem }) {
  const router = useRouter();
  const url = usePhotoUrl(item.photo);
  const slug = item.brand?.slug;

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
        <View style={s.badge}>
          <Text style={s.badgeText}>Featured</Text>
        </View>
      </View>

      <Text style={s.title} numberOfLines={1}>
        {item.title || "Untitled item"}
      </Text>
      <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>

      {slug ? (
        <Pressable
          onPress={() => router.push({ pathname: "/brand/[slug]", params: { slug } })}
          style={({ pressed }) => [s.brand, pressed && s.pressed]}
          hitSlop={6}
        >
          <Avatar url={item.brand?.logo_url} name={item.brand?.name} handle={slug} size={18} />
          <Text style={s.brandName} numberOfLines={1}>
            {item.brand?.name || `@${slug}`}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

const CARD = 190;

const s = StyleSheet.create({
  rail: { paddingHorizontal: spacing.lg, gap: spacing.md },
  card: { width: CARD, gap: 4 },
  frame: {
    width: CARD,
    height: CARD,
    borderRadius: radius.md,
    overflow: "hidden",
    backgroundColor: colors.surface,
  },
  photo: { width: "100%", height: "100%" },
  photoEmpty: { flex: 1, alignItems: "center", justifyContent: "center" },
  badge: {
    position: "absolute",
    top: spacing.sm,
    left: spacing.sm,
    paddingHorizontal: spacing.sm,
    paddingVertical: 3,
    borderRadius: radius.pill,
    backgroundColor: colors.ember,
  },
  badgeText: { ...type.label, fontSize: 9, color: colors.white },
  title: { ...type.small, color: colors.ink, marginTop: 2 },
  price: { ...type.price, fontSize: 15, color: colors.ink },
  brand: { flexDirection: "row", alignItems: "center", gap: 5, marginTop: 2 },
  pressed: { opacity: 0.6 },
  brandName: { ...type.small, fontFamily: fonts.sans, fontSize: 12, color: colors.textMuted, flexShrink: 1 },
});
