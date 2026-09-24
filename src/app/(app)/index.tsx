import { useFocusEffect, useRouter } from "expo-router";
import { useCallback } from "react";

import { EmptyState } from "@/components/empty-state";
import { Screen } from "@/components/screen";
import { ShopGrid } from "@/components/shop-grid";
import { useFeed } from "@/lib/shop";

/**
 * The buyer side of our own marketplace: every listing anyone has published,
 * newest first. A row only reaches here once publish() has stamped published_at,
 * which is also the only thing the public read policy lets through.
 */
export default function ShopScreen() {
  const router = useRouter();
  const { items, isLoading, refresh } = useFeed();

  // Something published on the Sell tab should be here by the time the buyer
  // taps back over, without waiting for a cold start.
  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  return (
    <Screen title="Shop">
      <ShopGrid
        items={items}
        onRefresh={refresh}
        refreshing={isLoading && items.length > 0}
        empty={
          isLoading ? undefined : (
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
