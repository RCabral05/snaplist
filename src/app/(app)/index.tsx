import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";

import { EmptyState } from "@/components/empty-state";
import { FeaturedRail } from "@/components/featured-rail";
import { Icon } from "@/components/icon";
import { Screen, SectionLabel } from "@/components/screen";
import { ShopGrid } from "@/components/shop-grid";
import { CATEGORIES, categoryLabel, type CategorySlug } from "@/lib/categories";
import { useFeatured, useFeed } from "@/lib/shop";
import { colors, radius, spacing, type } from "@/theme";

/**
 * The buyer's home. Search, categories, a curated rail, then everything else.
 *
 * The rail and the category row are hidden the moment the buyer searches or
 * picks a category: they came here to browse, and once they know what they want
 * a screen full of suggestions is in the way.
 */
export default function ShopScreen() {
  const router = useRouter();
  const [text, setText] = useState("");
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<CategorySlug | null>(null);

  // Debounced so typing is not a query per keystroke. The field keeps its own
  // immediate value; only the settled one reaches Postgres.
  useEffect(() => {
    const timer = setTimeout(() => setQuery(text), 300);
    return () => clearTimeout(timer);
  }, [text]);

  const { items, isLoading, refresh } = useFeed({ query, category });
  const { items: featuredItems, refresh: refreshFeatured } = useFeatured();

  // Depend on the two refresh functions, which are stable, and never on the
  // objects they came out of. A hook result in a dependency array re-runs the
  // effect on every render, and when the effect's job is to refetch, that is an
  // infinite loop rather than a slow screen.
  useFocusEffect(
    useCallback(() => {
      refresh();
      refreshFeatured();
    }, [refresh, refreshFeatured]),
  );

  const browsing = !query.trim() && !category;

  const header = (
    <View style={s.header}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={s.cats}
      >
        <CategoryChip
          label="All"
          on={!category}
          onPress={() => setCategory(null)}
        />
        {CATEGORIES.map((c) => (
          <CategoryChip
            key={c.slug}
            label={c.label}
            icon={c.slug}
            on={category === c.slug}
            onPress={() => setCategory(category === c.slug ? null : c.slug)}
          />
        ))}
      </ScrollView>

      {browsing && featuredItems.length ? (
        <View style={s.section}>
          <SectionLabel style={s.sectionLabel}>Featured</SectionLabel>
          <FeaturedRail items={featuredItems} />
        </View>
      ) : null}

      {items.length ? (
        <SectionLabel style={s.discover}>
          {category ? categoryLabel(category) : browsing ? "Discover" : "Results"}
        </SectionLabel>
      ) : null}
    </View>
  );

  return (
    <Screen title="Shop">
      <View style={s.searchWrap}>
        <View style={s.search}>
          <Icon name="magnifyingglass" size={16} color={colors.inkFaint} />
          <TextInput
            value={text}
            onChangeText={setText}
            placeholder="Search listings and brands"
            placeholderTextColor={colors.inkFaint}
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="search"
            style={s.input}
          />
          {text ? (
            <Pressable onPress={() => setText("")} hitSlop={10}>
              <Icon name="xmark.circle.fill" size={16} color={colors.inkFaint} />
            </Pressable>
          ) : null}
        </View>
      </View>

      <ShopGrid
        items={items}
        header={header}
        onRefresh={refresh}
        refreshing={isLoading && items.length > 0}
        empty={
          isLoading ? undefined : browsing ? (
            <EmptyState
              icon="bag"
              title="Nothing listed yet"
              body="The marketplace opens once the first sellers list something."
              actionLabel="Sell something"
              onAction={() => router.push("/sell")}
            />
          ) : (
            <EmptyState
              icon="magnifyingglass"
              title="Nothing matches"
              body={
                category && query.trim()
                  ? `No ${categoryLabel(category).toLowerCase()} mentions "${query.trim()}".`
                  : category
                    ? `Nothing in ${categoryLabel(category)} yet.`
                    : `No listing mentions "${query.trim()}". Try a brand, or a plainer word.`
              }
              actionLabel="Clear filters"
              onAction={() => {
                setText("");
                setCategory(null);
              }}
            />
          )
        }
      />
    </Screen>
  );
}

function CategoryChip({
  label,
  icon,
  on,
  onPress,
}: {
  label: string;
  icon?: CategorySlug;
  on: boolean;
  onPress: () => void;
}) {
  const found = CATEGORIES.find((c) => c.slug === icon);
  return (
    <Pressable onPress={onPress} style={[s.cat, on && s.catOn]}>
      {found ? (
        <Icon name={found.icon} size={13} color={on ? colors.white : colors.inkDim} />
      ) : null}
      <Text style={[s.catText, on && s.catTextOn]}>{label}</Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  searchWrap: { paddingHorizontal: spacing.lg, paddingBottom: spacing.md },
  search: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: radius.pill,
    backgroundColor: colors.paperAlt,
  },
  input: { ...type.body, fontSize: 15, color: colors.ink, flex: 1, paddingVertical: spacing.sm + 2 },

  // The header lives inside the grid's FlatList, so it scrolls away with the
  // products instead of pinning a third of the screen in place.
  header: { marginHorizontal: -spacing.lg, gap: spacing.lg, paddingBottom: spacing.xs },
  cats: { paddingHorizontal: spacing.lg, gap: spacing.xs },
  cat: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: 9,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.rule,
  },
  catOn: { backgroundColor: colors.ink, borderColor: colors.ink },
  catText: { ...type.label, fontSize: 10, color: colors.inkDim },
  catTextOn: { color: colors.white },

  section: { gap: spacing.sm },
  sectionLabel: { paddingHorizontal: spacing.lg },
  discover: { paddingHorizontal: spacing.lg },
});
