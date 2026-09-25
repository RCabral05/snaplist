import { useRouter, type Href } from "expo-router";
import { useCallback } from "react";

/**
 * Back, or somewhere sensible when there is no back.
 *
 * router.back() assumes this screen was pushed onto something, and several of
 * ours are not always: a deep link opens a brand page cold, and a Stack.Protected
 * guard flipping rebuilds the stack under whatever is mounted. Dispatching
 * GO_BACK in either case logs "not handled by any navigator" and leaves the
 * seller on a screen whose back button does nothing.
 *
 * The fallback is where that screen's back arrow ought to lead, not a generic
 * home - a brand page belongs back in Shop, a draft belongs in the Brand tab.
 */
export function useGoBack(fallback: Href) {
  const router = useRouter();
  return useCallback(() => {
    if (router.canGoBack()) router.back();
    else router.replace(fallback);
  }, [router, fallback]);
}
