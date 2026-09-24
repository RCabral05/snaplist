import { Image } from "expo-image";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback } from "react";
import { FlatList, Pressable, StyleSheet, Text, View } from "react-native";

import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { Screen } from "@/components/screen";
import { money, useListings, type ListingDraft } from "@/lib/listings";
import { adapterFor } from "@/lib/marketplaces";
import { colors, radius, spacing, type } from "@/theme";

export default function ListingsScreen() {
  const router = useRouter();
  const { drafts, channelsFor, refresh } = useListings();

  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  const renderItem = ({ item }: { item: ListingDraft }) => {
    const statuses = channelsFor(item.id);
    return (
      <Pressable
        onPress={() => router.push({ pathname: "/draft/[id]", params: { id: item.id } })}
        style={({ pressed }) => [s.card, pressed && s.pressed]}
      >
        {item.photos[0] ? (
          <Image source={{ uri: item.photos[0] }} style={s.thumb} contentFit="cover" />
        ) : (
          <View style={[s.thumb, s.thumbEmpty]}>
            <Icon name="photo" size={20} color={colors.inkFaint} weight="light" />
          </View>
        )}

        <View style={s.body}>
          <Text style={s.name} numberOfLines={1}>
            {item.title || "Untitled item"}
          </Text>
          <Text style={s.channels} numberOfLines={1}>
            {statuses.length
              ? statuses.map((c) => adapterFor(c.channel).name + " " + c.state).join("  ·  ")
              : "Draft · " + item.channels.map((c) => adapterFor(c).name).join(", ")}
          </Text>
        </View>

        {/* Price sits opposite the title rather than under it: scanning a column
            of prices down the trailing edge is the whole point of this list. */}
        <View style={s.trailing}>
          <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>
          <Icon name="chevron.right" size={13} color={colors.inkFaint} weight="semibold" />
        </View>
      </Pressable>
    );
  };

  return (
    <Screen title="Listings">
      <FlatList
        data={drafts}
        keyExtractor={(d) => d.id}
        renderItem={renderItem}
        contentContainerStyle={drafts.length ? s.list : s.listEmpty}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <EmptyState
            icon="square.stack"
            title="No listings yet"
            body="Photograph something on the Sell tab and it lands here as a draft."
            actionLabel="Take a photo"
            onAction={() => router.push("/sell")}
          />
        }
      />
    </Screen>
  );
}

const s = StyleSheet.create({
  list: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl, gap: spacing.sm },
  listEmpty: { flexGrow: 1 },
  card: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    padding: spacing.sm,
    paddingRight: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.paper,
  },
  pressed: { opacity: 0.6 },
  thumb: { width: 64, height: 64, borderRadius: radius.sm, backgroundColor: colors.surface },
  thumbEmpty: { alignItems: "center", justifyContent: "center" },
  body: { flex: 1, minWidth: 0, gap: 3 },
  name: { ...type.bodyMedium, color: colors.ink },
  channels: { ...type.small, fontSize: 13, color: colors.textMuted },
  trailing: { flexDirection: "row", alignItems: "center", gap: spacing.sm },
  price: { ...type.price, fontSize: 16, color: colors.ink },
});
