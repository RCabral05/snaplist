import { Image } from "expo-image";
import { useRouter } from "expo-router";
import { Dimensions, FlatList, Pressable, StyleSheet, Text, View } from "react-native";

import { money } from "@/lib/listings";
import { usePhotoUrl } from "@/lib/photos";
import type { ShopItem } from "@/lib/shop";
import { colors, radius, spacing, type } from "@/theme";

/** Nearly full width, so one card is the screen and the next one peeks. */
const CARD = Math.min(Dimensions.get("window").width - spacing.lg * 2 - 36, 340);

/**
 * The curated row, and the one place the app raises its voice.
 *
 * These are big, nearly full-bleed, with the title and price burned into the
 * bottom of the photograph over a gradient. A featured item that looks like a
 * grid card with a badge on it is not featured - it is a grid card with a badge
 * on it.
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
      snapToInterval={CARD + spacing.md}
      decelerationRate="fast"
      contentContainerStyle={s.rail}
    />
  );
}

function Card({ item }: { item: ShopItem }) {
  const router = useRouter();
  const url = usePhotoUrl(item.photo);

  return (
    <Pressable
      onPress={() => router.push({ pathname: "/item/[id]", params: { id: item.id } })}
      style={({ pressed }) => [s.card, pressed && s.pressed]}
    >
      {url ? (
        <Image source={{ uri: url }} style={s.photo} contentFit="cover" transition={160} />
      ) : (
        <View style={s.photoEmpty} />
      )}

      {/* Four stacked bands instead of a gradient. expo-linear-gradient is a
          native module and adding one would mean a new dev client build for a
          decoration; at this height the banding is not visible. */}
      <View style={s.scrim} pointerEvents="none">
        <View style={[s.band, { backgroundColor: "rgba(10,9,7,0.12)" }]} />
        <View style={[s.band, { backgroundColor: "rgba(10,9,7,0.34)" }]} />
        <View style={[s.band, { backgroundColor: "rgba(10,9,7,0.58)" }]} />
        <View style={[s.band, { backgroundColor: "rgba(10,9,7,0.78)" }]} />
      </View>

      <View style={s.caption}>
        {item.brand?.name ? (
          <Text style={s.brand} numberOfLines={1}>
            {item.brand.name}
          </Text>
        ) : null}
        <Text style={s.title} numberOfLines={2}>
          {item.title || "Untitled item"}
        </Text>
        <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>
      </View>
    </Pressable>
  );
}

const s = StyleSheet.create({
  rail: { paddingHorizontal: spacing.lg, gap: spacing.md },
  card: {
    width: CARD,
    height: CARD * 1.18,
    borderRadius: radius.lg,
    overflow: "hidden",
    backgroundColor: colors.paperAlt,
    justifyContent: "flex-end",
  },
  pressed: { opacity: 0.9 },
  photo: { position: "absolute", top: 0, left: 0, right: 0, bottom: 0 },
  photoEmpty: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: colors.sand,
  },
  scrim: { position: "absolute", left: 0, right: 0, bottom: 0, height: "46%" },
  band: { flex: 1 },
  caption: { padding: spacing.md, gap: 1 },
  brand: { ...type.label, fontSize: 9, color: "rgba(255,255,255,0.72)" },
  title: { ...type.title, fontSize: 22, lineHeight: 25, color: colors.white },
  price: { ...type.price, fontSize: 20, color: colors.white, marginTop: 2 },
});
