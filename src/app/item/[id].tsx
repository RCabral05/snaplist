import { Image } from "expo-image";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useState } from "react";
import { Alert, Dimensions, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { Avatar } from "@/components/avatar";
import { Button } from "@/components/button";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { categoryLabel } from "@/lib/categories";
import { money } from "@/lib/listings";
import type { Condition } from "@/lib/marketplaces";
import { useGoBack } from "@/lib/navigation";
import { usePhotoUrl } from "@/lib/photos";
import { useItem } from "@/lib/shop";
import { colors, radius, shadow, spacing, type } from "@/theme";

const CONDITION: Record<Condition, string> = {
  new: "New",
  like_new: "Like new",
  good: "Good",
  fair: "Fair",
  parts: "For parts",
};

const HERO = Dimensions.get("window").height * 0.52;

/**
 * One listing, for a buyer.
 *
 * The photograph runs edge to edge under the status bar and the content sheet
 * lifts over it - the object is the page, and a picture inside a padded card
 * with a header above it is a database row with a picture in it. Buying sits in
 * a bar pinned to the bottom, so it is reachable without scrolling back.
 *
 * It reads through the same public policy as the feed, so a draft cannot be
 * opened by guessing an id: the row is invisible until published_at is set.
 */
export default function ItemScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const goBack = useGoBack("/");
  const { item, isLoading } = useItem(id);

  const back = (
    <Pressable onPress={goBack} hitSlop={14} style={[s.back, { top: insets.top + spacing.sm }]}>
      <Icon name="chevron.left" size={17} color={colors.ink} weight="semibold" />
    </Pressable>
  );

  if (!item) {
    return (
      <View style={s.safe}>
        {back}
        {isLoading ? (
          <View style={s.center}>
            <Text style={s.muted}>Loading…</Text>
          </View>
        ) : (
          <EmptyState
            icon="questionmark.circle"
            title="This listing is gone"
            body="It may have sold, or the seller took it down."
            actionLabel="Back to Shop"
            onAction={() => router.replace("/")}
          />
        )}
      </View>
    );
  }

  const slug = item.brand?.slug;

  return (
    <View style={s.safe}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 120 + insets.bottom }}
        showsVerticalScrollIndicator={false}
      >
        <Gallery photos={item.photos} height={HERO} />

        <View style={s.sheet}>
          {item.brand?.name || slug ? (
            <Text style={s.eyebrow}>{item.brand?.name || slug}</Text>
          ) : null}
          <Text style={s.title}>{item.title || "Untitled item"}</Text>
          <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>

          <View style={s.tags}>
            <Tag label={CONDITION[item.condition]} />
            {item.categorySlug ? <Tag label={categoryLabel(item.categorySlug)} /> : null}
          </View>

          {item.description ? <Text style={s.description}>{item.description}</Text> : null}

          {slug ? (
            <Pressable
              onPress={() => router.push({ pathname: "/brand/[slug]", params: { slug } })}
              style={({ pressed }) => [s.seller, pressed && s.pressed]}
            >
              <Avatar url={item.brand?.logo_url} name={item.brand?.name} handle={slug} size={42} />
              <View style={s.sellerBody}>
                <Text style={s.sellerName} numberOfLines={1}>
                  {item.brand?.name || `@${slug}`}
                </Text>
                <Text style={s.sellerHandle} numberOfLines={1}>
                  Visit @{slug}
                </Text>
              </View>
              <Icon name="chevron.right" size={14} color={colors.inkFaint} weight="semibold" />
            </Pressable>
          ) : null}

          <Text style={s.note}>
            Listed {new Date(item.publishedAt).toLocaleDateString()}
          </Text>
        </View>
      </ScrollView>

      {back}

      {/* Pinned, because the price and the decision belong together and the
          description can run long. */}
      <View style={[s.bar, { paddingBottom: insets.bottom + spacing.sm }]}>
        <View style={s.barPrice}>
          <Text style={s.barLabel}>Price</Text>
          <Text style={s.barAmount}>{money(item.priceCents, item.currency)}</Text>
        </View>
        <Button
          label="Buy"
          style={s.buy}
          onPress={() =>
            Alert.alert(
              "Not available yet",
              "Buying on Snaplist needs payments and a checkout, neither of which is built. " +
                "For now this page is here so listings can be browsed and shared.",
            )
          }
        />
      </View>
    </View>
  );
}

/**
 * Every angle, paged. Dots rather than a counter, and no dots at all for a single
 * photo - a "1 / 1" is a piece of chrome telling you there is nothing to see.
 */
function Gallery({ photos, height }: { photos: string[]; height: number }) {
  const [index, setIndex] = useState(0);
  const width = Dimensions.get("window").width;

  if (!photos.length) {
    return (
      <View style={[s.hero, { height }]}>
        <View style={s.photoEmpty}>
          <Icon name="photo" size={30} color={colors.ruleStrong} weight="light" />
        </View>
      </View>
    );
  }

  return (
    <View style={[s.hero, { height }]}>
      <ScrollView
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onMomentumScrollEnd={(e) =>
          setIndex(Math.round(e.nativeEvent.contentOffset.x / width))
        }
      >
        {photos.map((p) => (
          <Slide key={p} photo={p} width={width} height={height} />
        ))}
      </ScrollView>

      {photos.length > 1 ? (
        <View style={s.dots}>
          {photos.map((p, i) => (
            <View key={p} style={[s.dot, i === index && s.dotOn]} />
          ))}
        </View>
      ) : null}
    </View>
  );
}

function Slide({ photo, width, height }: { photo: string; width: number; height: number }) {
  const url = usePhotoUrl(photo);
  return url ? (
    <Image source={{ uri: url }} style={{ width, height }} contentFit="cover" transition={180} />
  ) : (
    <View style={{ width, height, backgroundColor: colors.paperAlt }} />
  );
}

function Tag({ label }: { label: string }) {
  return (
    <View style={s.tag}>
      <Text style={s.tagText}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  muted: { ...type.body, color: colors.textMuted },

  back: {
    position: "absolute",
    left: spacing.lg,
    zIndex: 10,
    width: 38,
    height: 38,
    borderRadius: radius.pill,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "rgba(251,250,248,0.92)",
    ...shadow.lift,
  },

  hero: { width: "100%", backgroundColor: colors.paperAlt },
  dots: {
    position: "absolute",
    bottom: 40,
    left: 0,
    right: 0,
    flexDirection: "row",
    justifyContent: "center",
    gap: 6,
  },
  dot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: "rgba(255,255,255,0.45)",
  },
  dotOn: { backgroundColor: colors.white },
  photoEmpty: { flex: 1, alignItems: "center", justifyContent: "center" },

  // Lifted over the photograph, so the image runs under it rather than stopping
  // at a hard edge.
  sheet: {
    marginTop: -radius.xl,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    backgroundColor: colors.paper,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    gap: spacing.sm,
  },
  eyebrow: { ...type.label, color: colors.inkFaint },
  title: { ...type.display, color: colors.ink },
  price: { ...type.priceBig, color: colors.ink },

  tags: { flexDirection: "row", flexWrap: "wrap", gap: spacing.xs, marginTop: spacing.xs },
  tag: {
    paddingHorizontal: spacing.md,
    paddingVertical: 7,
    borderRadius: radius.pill,
    backgroundColor: colors.paperAlt,
  },
  tagText: { ...type.label, fontSize: 9, color: colors.inkDim },

  description: {
    ...type.body,
    fontSize: 16,
    color: colors.textMuted,
    lineHeight: 25,
    marginTop: spacing.sm,
  },

  seller: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.rule,
    marginTop: spacing.md,
  },
  pressed: { opacity: 0.7 },
  sellerBody: { flex: 1, minWidth: 0, gap: 1 },
  sellerName: { ...type.bodyMedium, fontSize: 15, color: colors.ink },
  sellerHandle: { ...type.small, fontSize: 13, color: colors.ember },

  note: { ...type.small, fontSize: 12, color: colors.inkFaint, marginTop: spacing.md },

  bar: {
    position: "absolute",
    left: 0,
    right: 0,
    bottom: 0,
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    backgroundColor: colors.surface,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.rule,
  },
  barPrice: { flex: 1, gap: 1 },
  barLabel: { ...type.label, fontSize: 9, color: colors.inkFaint },
  barAmount: { ...type.price, fontSize: 24, color: colors.ink },
  buy: { minWidth: 150 },
});
