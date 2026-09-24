import { Image } from "expo-image";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useMemo } from "react";
import { Alert, FlatList, Pressable, StyleSheet, Text, View } from "react-native";

import { Avatar } from "@/components/avatar";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { Screen, SectionLabel } from "@/components/screen";
import { useBrands } from "@/lib/brands";
import { useConnections } from "@/lib/connections";
import { money, useListings, type ListingDraft } from "@/lib/listings";
import { adapterFor, adapters } from "@/lib/marketplaces";
import { usePhotoUrl } from "@/lib/photos";
import { colors, fonts, radius, spacing, type } from "@/theme";

/**
 * The active brand's home: how it is doing, what it is connected to, and
 * everything it has listed. Products are what hangs off a brand today; when
 * events arrive they get a section here rather than a tab of their own.
 */
export default function BrandScreen() {
  const router = useRouter();
  const { active, brands, setActive } = useBrands();
  const { drafts, channelsFor, refresh } = useListings();
  const { isConnected, disconnect } = useConnections();

  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  // Counted from the per-channel states rather than the drafts: a listing can be
  // live on one channel and failed on another, and pretending otherwise is the
  // thing publish() was built not to do.
  const counts = useMemo(() => {
    let live = 0;
    let failed = 0;
    let draft = 0;
    for (const d of drafts) {
      const states = channelsFor(d.id);
      if (!states.length) draft += 1;
      else if (states.some((c) => c.state === "live")) live += 1;
      if (states.some((c) => c.state === "failed")) failed += 1;
    }
    return { live, failed, draft };
  }, [drafts, channelsFor]);

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
              // Round-robin rather than a picker: with a handful of brands the
              // sheet costs more taps than it saves.
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

      <View style={s.stats}>
        <Stat label="Live" value={counts.live} tone={colors.live} />
        <Stat label="Drafts" value={counts.draft} />
        <Stat label="Failed" value={counts.failed} tone={counts.failed ? colors.failed : undefined} />
      </View>

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

      {drafts.length ? <SectionLabel style={s.listingsLabel}>Listings</SectionLabel> : null}
    </View>
  );

  const renderItem = ({ item }: { item: ListingDraft }) => {
    const statuses = channelsFor(item.id);
    return (
      <Pressable
        onPress={() => router.push({ pathname: "/draft/[id]", params: { id: item.id } })}
        style={({ pressed }) => [s.card, pressed && s.pressed]}
      >
        <Thumb photo={item.photos[0]} />
        <View style={s.body}>
          <Text style={s.name} numberOfLines={1}>
            {item.title || "Untitled item"}
          </Text>
          <Text style={s.meta} numberOfLines={1}>
            {statuses.length
              ? statuses.map((c) => adapterFor(c.channel).name + " " + c.state).join("  ·  ")
              : "Draft · " + item.channels.map((c) => adapterFor(c).name).join(", ")}
          </Text>
        </View>
        <View style={s.trailing}>
          <Text style={s.price}>{money(item.priceCents, item.currency)}</Text>
          <Icon name="chevron.right" size={13} color={colors.inkFaint} weight="semibold" />
        </View>
      </Pressable>
    );
  };

  return (
    <Screen title={active?.name || "Brand"}>
      <FlatList
        data={drafts}
        keyExtractor={(d) => d.id}
        renderItem={renderItem}
        ListHeaderComponent={header}
        contentContainerStyle={s.list}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <EmptyState
            icon="square.stack"
            title="Nothing listed yet"
            body="Photograph something on the Sell tab and it lands here as a draft."
            actionLabel="Take a photo"
            onAction={() => router.push("/sell")}
          />
        }
      />
    </Screen>
  );
}

function Stat({ label, value, tone }: { label: string; value: number; tone?: string }) {
  return (
    <View style={s.stat}>
      <Text style={[s.statValue, tone ? { color: tone } : null]}>{value}</Text>
      <Text style={s.statLabel}>{label}</Text>
    </View>
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

  stats: {
    flexDirection: "row",
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
  },
  stat: { flex: 1, alignItems: "center", gap: 2 },
  statValue: { ...type.display, fontSize: 24, color: colors.ink },
  statLabel: { ...type.label, fontSize: 10, color: colors.textFaint },

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
  listingsLabel: { marginTop: spacing.sm },

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
  meta: { ...type.small, fontSize: 13, color: colors.textMuted },
  trailing: { flexDirection: "row", alignItems: "center", gap: spacing.sm },
  price: { ...type.price, fontSize: 16, color: colors.ink },
});
