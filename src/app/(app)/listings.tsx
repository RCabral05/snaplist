import { Image } from "expo-image";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback } from "react";
import { FlatList, Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { adapterFor } from "@/lib/marketplaces";
import { money, useListings, type ListingDraft } from "@/lib/listings";
import { colors, radius, spacing, type } from "@/theme";

export default function ListingsScreen() {
  const router = useRouter();
  const { drafts, channelsFor, refresh } = useListings();

  useFocusEffect(useCallback(() => { refresh(); }, [refresh]));

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
          <View style={[s.thumb, s.thumbEmpty]} />
        )}
        <View style={s.cardBody}>
          <Text style={s.cardTitle} numberOfLines={1}>
            {item.title || "Untitled item"}
          </Text>
          <Text style={s.cardPrice}>{money(item.priceCents, item.currency)}</Text>
          <Text style={s.cardChannels} numberOfLines={1}>
            {statuses.length
              ? statuses.map((c) => adapterFor(c.channel).name + " " + c.state).join("  ·  ")
              : "Draft · " + item.channels.map((c) => adapterFor(c).name).join(", ")}
          </Text>
        </View>
      </Pressable>
    );
  };

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <View style={s.header}>
        <Text style={s.title}>Listings</Text>
      </View>
      <FlatList
        data={drafts}
        keyExtractor={(d) => d.id}
        renderItem={renderItem}
        contentContainerStyle={s.list}
        ListEmptyComponent={
          <View style={s.empty}>
            <Text style={s.emptyTitle}>No listings yet</Text>
            <Text style={s.emptyBody}>Snap something on the Sell tab.</Text>
          </View>
        }
      />
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  header: { paddingHorizontal: spacing.md, paddingVertical: spacing.md },
  title: { ...type.display, color: colors.ink },
  list: { paddingHorizontal: spacing.md, paddingBottom: spacing.xxl, gap: spacing.sm },
  card: {
    flexDirection: "row",
    gap: spacing.md,
    padding: spacing.sm,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.paper,
  },
  pressed: { opacity: 0.7 },
  thumb: { width: 72, height: 72, borderRadius: radius.sm, backgroundColor: colors.surfaceHigh },
  thumbEmpty: { borderWidth: 1, borderColor: colors.border },
  cardBody: { flex: 1, justifyContent: "center", gap: 2 },
  cardTitle: { ...type.bodyMedium, color: colors.ink },
  cardPrice: { ...type.price, color: colors.ink },
  cardChannels: { ...type.small, color: colors.textMuted },
  empty: { alignItems: "center", paddingTop: spacing.xxl, gap: spacing.xs },
  emptyTitle: { ...type.title, color: colors.ink },
  emptyBody: { ...type.body, color: colors.textMuted },
});
