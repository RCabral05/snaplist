import { Image } from "expo-image";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useMemo, useState } from "react";
import { Alert, FlatList, Pressable, StyleSheet, Text, View } from "react-native";

import { Avatar } from "@/components/avatar";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { Screen } from "@/components/screen";
import { useBrands } from "@/lib/brands";
import { useConnections } from "@/lib/connections";
import { money, useListings, type ListingDraft } from "@/lib/listings";
import { adapterFor, adapters } from "@/lib/marketplaces";
import { usePhotoUrl } from "@/lib/photos";
import { colors, fonts, radius, spacing, type } from "@/theme";

type Filter = "all" | "live" | "draft";

/**
 * The active brand's home: how it is doing, what it is connected to, and
 * everything it has listed.
 *
 * Whether a listing is live comes from listings.published_at - the same column
 * the Shop feed reads. It used to come from a per-device cache of channel
 * states, which meant an item could be visibly for sale in Shop and still say
 * "Draft" here: two sources of truth for one fact, disagreeing.
 */
export default function BrandScreen() {
  const router = useRouter();
  const { active, brands, setActive } = useBrands();
  const { drafts, refresh } = useListings();
  const { isConnected, disconnect } = useConnections();
  const [filter, setFilter] = useState<Filter>("all");

  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  const live = useMemo(() => drafts.filter((d) => d.publishedAt).length, [drafts]);
  const unpublished = drafts.length - live;

  const shown = useMemo(() => {
    if (filter === "live") return drafts.filter((d) => d.publishedAt);
    if (filter === "draft") return drafts.filter((d) => !d.publishedAt);
    return drafts;
  }, [drafts, filter]);

  const header = (
    <View style={s.head}>
      <Pressable
        onPress={() => router.push("/brand-settings")}
        style={({ pressed }) => [s.identity, pressed && s.pressed]}
      >
        <Avatar url={active?.logo_url} name={active?.name} handle={active?.slug} size={44} />
        <View style={s.who}>
          <Text style={s.brandName} numberOfLines={1}>
            {active?.name || "Your brand"}
          </Text>
          <Text style={s.brandHandle} numberOfLines={1}>
            @{active?.slug}
          </Text>
        </View>
        {brands.length > 1 ? (
          <Pressable
            onPress={() => {
              const i = brands.findIndex((b) => b.id === active?.id);
              setActive(brands[(i + 1) % brands.length].id);
            }}
            hitSlop={10}
            style={s.switch}
          >
            <Icon name="arrow.triangle.2.circlepath" size={14} color={colors.inkDim} />
            <Text style={s.switchText}>Switch</Text>
          </Pressable>
        ) : (
          <Icon name="chevron.right" size={14} color={colors.inkFaint} weight="semibold" />
        )}
      </Pressable>

      <View style={s.channels}>
        {adapters
          .filter((a) => a.requiresConnection)
          .map((adapter) => {
            const on = isConnected(adapter.id);
            return (
              <Pressable
                key={adapter.id}
                onPress={() => {
                  if (on) {
                    disconnect(adapter.id).catch((e) =>
                      Alert.alert("Could not disconnect", e?.message ?? ""),
                    );
                    return;
                  }
                  Alert.alert(
                    "Not available yet",
                    "Connecting " +
                      adapter.name +
                      " needs the backend to complete the OAuth handshake and store the token. Nothing to connect to yet.",
                  );
                }}
                style={({ pressed }) => [s.chip, on && s.chipOn, pressed && s.pressed]}
              >
                <View style={[s.dot, on && s.dotOn]} />
                <Text style={[s.chipText, on && s.chipTextOn]}>{adapter.name}</Text>
              </Pressable>
            );
          })}

        {active ? (
          <Pressable
            onPress={() =>
              router.push({ pathname: "/brand/[slug]", params: { slug: active.slug } })
            }
            style={({ pressed }) => [s.chip, pressed && s.pressed]}
          >
            <Text style={s.chipText}>View storefront</Text>
            <Icon name="arrow.up.right" size={11} color={colors.inkDim} weight="semibold" />
          </Pressable>
        ) : null}
      </View>

      {drafts.length ? (
        <View style={s.filters}>
          <FilterTab label="All" count={drafts.length} on={filter === "all"} onPress={() => setFilter("all")} />
          <FilterTab label="Live" count={live} on={filter === "live"} onPress={() => setFilter("live")} />
          <FilterTab
            label="Drafts"
            count={unpublished}
            on={filter === "draft"}
            onPress={() => setFilter("draft")}
          />
        </View>
      ) : null}
    </View>
  );

  const renderItem = ({ item }: { item: ListingDraft }) => (
    <Pressable
      onPress={() => router.push({ pathname: "/draft/[id]", params: { id: item.id } })}
      style={({ pressed }) => [s.card, pressed && s.pressed]}
    >
      <Thumb photo={item.photos[0]} />
      <View style={s.body}>
        <Text style={s.name} numberOfLines={1}>
          {item.title || "Untitled item"}
        </Text>
        <View style={s.stateRow}>
          <View style={[s.stateDot, item.publishedAt ? s.stateDotLive : null]} />
          <Text style={s.meta} numberOfLines={1}>
            {item.publishedAt
              ? "Live on Snaplist"
              : "Draft · " + item.channels.map((c) => adapterFor(c).name).join(", ")}
          </Text>
        </View>
      </View>
      <View style={s.trailing}>
        <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>
        <Icon name="chevron.right" size={13} color={colors.inkFaint} weight="semibold" />
      </View>
    </Pressable>
  );

  return (
    <Screen title={active?.name || "Brand"}>
      <FlatList
        data={shown}
        keyExtractor={(d) => d.id}
        renderItem={renderItem}
        ListHeaderComponent={header}
        contentContainerStyle={s.list}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          drafts.length ? (
            <View style={s.none}>
              <Text style={s.noneText}>
                {filter === "live" ? "Nothing is live yet." : "No drafts - everything is live."}
              </Text>
            </View>
          ) : (
            <EmptyState
              icon="square.stack"
              title="Nothing listed yet"
              body="Photograph something on the Sell tab and it lands here as a draft."
              actionLabel="Take a photo"
              onAction={() => router.push("/sell")}
            />
          )
        }
      />
    </Screen>
  );
}

function FilterTab({
  label,
  count,
  on,
  onPress,
}: {
  label: string;
  count: number;
  on: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[s.filter, on && s.filterOn]}>
      <Text style={[s.filterText, on && s.filterTextOn]}>
        {label} {count}
      </Text>
    </Pressable>
  );
}

/** Its own component because resolving a private object to a signed URL is a hook. */
function Thumb({ photo }: { photo?: string }) {
  const url = usePhotoUrl(photo);
  if (url) return <Image source={{ uri: url }} style={s.thumb} contentFit="cover" />;
  return (
    <View style={[s.thumb, s.thumbEmpty]}>
      <Icon name="photo" size={20} color={colors.inkFaint} weight="light" />
    </View>
  );
}

const s = StyleSheet.create({
  pressed: { opacity: 0.6 },
  list: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl, gap: spacing.sm },

  head: { gap: spacing.md, paddingBottom: spacing.xs },
  identity: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
  },
  who: { flex: 1, minWidth: 0, gap: 1 },
  brandName: { ...type.bodyMedium, fontSize: 15, color: colors.ink },
  brandHandle: { ...type.small, fontSize: 13, color: colors.ember },
  switch: { flexDirection: "row", alignItems: "center", gap: 4 },
  switchText: { ...type.small, fontSize: 12, color: colors.inkDim },

  channels: { flexDirection: "row", flexWrap: "wrap", gap: spacing.sm },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: 8,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.border,
  },
  chipOn: { borderColor: colors.live },
  dot: { width: 7, height: 7, borderRadius: 4, backgroundColor: colors.ruleStrong },
  dotOn: { backgroundColor: colors.live },
  chipText: { ...type.small, fontFamily: fonts.sansMedium, fontSize: 13, color: colors.inkDim },
  chipTextOn: { color: colors.ink },

  // Counts sit on the tabs rather than in a separate stat block: three numbers
  // above three filters saying the same three numbers was one row too many.
  filters: { flexDirection: "row", gap: spacing.xs },
  filter: {
    paddingHorizontal: spacing.md,
    paddingVertical: 7,
    borderRadius: radius.pill,
    backgroundColor: colors.surface,
  },
  filterOn: { backgroundColor: colors.ink },
  filterText: { ...type.small, fontFamily: fonts.sansMedium, fontSize: 13, color: colors.inkDim },
  filterTextOn: { color: colors.white },

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
  thumb: { width: 64, height: 64, borderRadius: radius.sm, backgroundColor: colors.surface },
  thumbEmpty: { alignItems: "center", justifyContent: "center" },
  body: { flex: 1, minWidth: 0, gap: 3 },
  name: { ...type.bodyMedium, color: colors.ink },
  stateRow: { flexDirection: "row", alignItems: "center", gap: 6 },
  stateDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.draft },
  stateDotLive: { backgroundColor: colors.live },
  meta: { ...type.small, fontSize: 13, color: colors.textMuted, flexShrink: 1 },
  trailing: { flexDirection: "row", alignItems: "center", gap: spacing.sm },
  price: { ...type.price, fontSize: 16, color: colors.ink },

  none: { paddingTop: spacing.xl, alignItems: "center" },
  noneText: { ...type.small, color: colors.textMuted },
});
