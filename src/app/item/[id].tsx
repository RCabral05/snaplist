import { Image } from "expo-image";
import { useLocalSearchParams, useRouter } from "expo-router";
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

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
import { colors, fonts, radius, spacing, type } from "@/theme";

const CONDITION: Record<Condition, string> = {
  new: "New",
  like_new: "Like new",
  good: "Good",
  fair: "Fair",
  parts: "For parts",
};

/**
 * One listing, for a buyer.
 *
 * It reads through the same public policy as the feed, so a draft cannot be
 * opened by guessing its id - the row simply is not visible until published_at
 * is set.
 */
export default function ItemScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const goBack = useGoBack("/");
  const { item, isLoading } = useItem(id);
  const photo = usePhotoUrl(item?.photo);

  const nav = (
    <View style={s.nav}>
      <Pressable onPress={goBack} hitSlop={12} style={s.navButton}>
        <Icon name="chevron.left" size={18} color={colors.ink} weight="semibold" />
      </Pressable>
    </View>
  );

  if (!item) {
    return (
      <SafeAreaView style={s.safe} edges={["top"]}>
        {nav}
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
      </SafeAreaView>
    );
  }

  const slug = item.brand?.slug;

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      {nav}
      <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false}>
        <View style={s.frame}>
          {photo ? (
            <Image source={{ uri: photo }} style={s.photo} contentFit="cover" transition={140} />
          ) : (
            <View style={s.photoEmpty}>
              <Icon name="photo" size={28} color={colors.inkFaint} weight="light" />
            </View>
          )}
        </View>

        <View style={s.headline}>
          <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>
          <Text style={s.title}>{item.title || "Untitled item"}</Text>
        </View>

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
            <Avatar url={item.brand?.logo_url} name={item.brand?.name} handle={slug} size={40} />
            <View style={s.sellerBody}>
              <Text style={s.sellerName} numberOfLines={1}>
                {item.brand?.name || `@${slug}`}
              </Text>
              <Text style={s.sellerHandle} numberOfLines={1}>
                @{slug}
              </Text>
            </View>
            <Icon name="chevron.right" size={14} color={colors.inkFaint} weight="semibold" />
          </Pressable>
        ) : null}

        {/* A real button that says the truth, rather than a checkout that is not
            there. Same pattern as connecting a channel: the app admits what is
            missing instead of pretending. */}
        <Button
          label="Buy"
          onPress={() =>
            Alert.alert(
              "Not available yet",
              "Buying on Snaplist needs payments and a checkout, neither of which is built. " +
                "For now this page is here so listings can be browsed and shared.",
            )
          }
          style={s.buy}
        />
        <Text style={s.note}>Listed {new Date(item.publishedAt).toLocaleDateString()}</Text>
      </ScrollView>
    </SafeAreaView>
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
  nav: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.xs },
  navButton: { alignSelf: "flex-start" },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  muted: { ...type.body, color: colors.textMuted },

  body: { padding: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.xxl, gap: spacing.md },
  frame: {
    width: "100%",
    aspectRatio: 1,
    borderRadius: radius.lg,
    overflow: "hidden",
    backgroundColor: colors.surface,
  },
  photo: { width: "100%", height: "100%" },
  photoEmpty: { flex: 1, alignItems: "center", justifyContent: "center" },

  headline: { gap: 2 },
  price: { ...type.display, fontSize: 28, color: colors.ink },
  title: { ...type.body, fontSize: 17, color: colors.ink, lineHeight: 23 },

  tags: { flexDirection: "row", flexWrap: "wrap", gap: spacing.xs },
  tag: {
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
    borderRadius: radius.pill,
    backgroundColor: colors.surface,
  },
  tagText: { ...type.small, fontFamily: fonts.sansMedium, fontSize: 12, color: colors.inkDim },

  description: { ...type.body, fontSize: 15, color: colors.textMuted, lineHeight: 22 },

  seller: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
  },
  pressed: { opacity: 0.6 },
  sellerBody: { flex: 1, minWidth: 0, gap: 1 },
  sellerName: { ...type.bodyMedium, fontSize: 15, color: colors.ink },
  sellerHandle: { ...type.small, fontSize: 13, color: colors.ember },

  buy: { marginTop: spacing.xs },
  note: { ...type.small, fontSize: 12, color: colors.textFaint, textAlign: "center" },
});
