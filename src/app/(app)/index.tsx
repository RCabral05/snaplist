import { useRouter } from "expo-router";

import { EmptyState } from "@/components/empty-state";
import { Screen } from "@/components/screen";
import { MOCK } from "@/lib/api";

/**
 * The buyer side of our own marketplace. It has nothing to show until the backend
 * serves a feed, and saying so beats a grid of placeholder rectangles.
 */
export default function ShopScreen() {
  const router = useRouter();

  return (
    <Screen title="Shop">
      <EmptyState
        icon="bag"
        title="Nothing listed yet"
        // The MOCK branch used to print EXPO_PUBLIC_API_URL at the seller. That
        // is a note to whoever is building the backend, not something a person
        // holding the app can act on - it belongs in the README.
        body={
          MOCK
            ? "The marketplace opens once the first sellers list something."
            : "Be the first to list something."
        }
        actionLabel="Sell something"
        onAction={() => router.push("/sell")}
      />
    </Screen>
  );
}
