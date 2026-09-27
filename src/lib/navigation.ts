import { useRouter, type Href } from "expo-router";
import { useCallback } from "react";

/**
 * Back, or somewhere sensible when there is no back.
 *
 * router.back() assumes this screen was pushed onto something, and several of
 * ours are not always: the scheme is registered, so a link can open a screen
 * cold, and a Stack.Protected guard flipping rebuilds the stack under whatever
 * is mounted. Dispatching GO_BACK in either case logs "not handled by any
 * navigator" and leaves a back button that quietly does nothing.
 *
 * The fallback is wherever that screen's back arrow ought to lead.
 */
export function useGoBack(fallback: Href) {
  const router = useRouter();
  return useCallback(() => {
    if (router.canGoBack()) router.back();
    else router.replace(fallback);
  }, [router, fallback]);
}
