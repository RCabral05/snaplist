import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { Pressable, StyleSheet, TextInput, View } from "react-native";

import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { Screen } from "@/components/screen";
import { ShopGrid } from "@/components/shop-grid";
import { useFeed } from "@/lib/shop";
import { colors, radius, spacing, type } from "@/theme";

/**
 * The buyer side of our own marketplace: everything anyone has published, newest
 * first, or whatever matches the search.
 */
export default function ShopScreen() {
  const router = useRouter();
  const [text, setText] = useState("");
  const [query, setQuery] = useState("");

  // Debounced so typing does not fire a query per keystroke. The field keeps its
  // own immediate value; only the settled one reaches Postgres.
  useEffect(() => {
    const timer = setTimeout(() => setQuery(text), 300);
    return () => clearTimeout(timer);
  }, [text]);

  const { items, isLoading, refresh } = useFeed(query);

  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  const searching = query.trim().length > 0;

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
            clearButtonMode="never"
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
        onRefresh={refresh}
        refreshing={isLoading && items.length > 0}
        empty={
          isLoading ? undefined : searching ? (
            <EmptyState
              icon="magnifyingglass"
              title="Nothing matches"
              body={`No listing mentions "${query.trim()}". Try a brand, or a plainer word.`}
            />
          ) : (
            <EmptyState
              icon="bag"
              title="Nothing listed yet"
              body="The marketplace opens once the first sellers list something."
              actionLabel="Sell something"
              onAction={() => router.push("/sell")}
            />
          )
        }
      />
    </Screen>
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
    backgroundColor: colors.surface,
  },
  input: { ...type.body, fontSize: 15, color: colors.ink, flex: 1, paddingVertical: spacing.sm + 2 },
});
