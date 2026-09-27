import * as AppleAuthentication from "expo-apple-authentication";
import { useEffect, useState } from "react";
import { Alert, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { googleConfigured, useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

/**
 * One statement, two ways in, and a lot of black.
 *
 * The buttons sit at the bottom where a thumb is, and the space above them is
 * empty on purpose - this is the only screen with nothing to do on it, so
 * filling it would only be filling it.
 */
export default function SignInScreen() {
  const { signInWithApple, signInWithGoogle } = useAuth();
  const [busy, setBusy] = useState<"apple" | "google" | null>(null);
  // null while we ask. Rendering the Apple button when its native view is not in
  // the binary paints a red "Unimplemented component" box, so ask first.
  const [appleReady, setAppleReady] = useState<boolean | null>(null);

  useEffect(() => {
    let alive = true;
    AppleAuthentication.isAvailableAsync()
      .catch(() => false)
      .then((ok) => {
        if (alive) setAppleReady(ok);
      });
    return () => {
      alive = false;
    };
  }, []);

  const run = async (who: "apple" | "google", fn: () => Promise<unknown>) => {
    setBusy(who);
    try {
      await fn();
    } catch (e: any) {
      Alert.alert("Could not sign in", e?.message ?? "Something went wrong.");
    } finally {
      setBusy(null);
    }
  };

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.head}>
        <View style={s.dot} />
        <Text style={s.mark}>Snaplist</Text>
      </View>

      <View style={s.statement}>
        <Text style={s.headline}>Welcome{"\n"}back.</Text>
        <Text style={s.sub}>Sign in and pick up where you left off.</Text>
      </View>

      <View style={s.actions}>
        {appleReady ? (
          <AppleAuthentication.AppleAuthenticationButton
            buttonType={AppleAuthentication.AppleAuthenticationButtonType.CONTINUE}
            // White on a dark screen; the black variant disappears into it.
            buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.WHITE}
            cornerRadius={radius.md}
            style={s.apple}
            onPress={() => run("apple", signInWithApple)}
          />
        ) : null}

        {googleConfigured ? (
          <Button
            label="Continue with Google"
            variant="secondary"
            onPress={() => run("google", signInWithGoogle)}
            loading={busy === "google"}
            disabled={busy !== null}
          />
        ) : null}

        {appleReady === false && !googleConfigured ? (
          <Text style={s.note}>
            No sign-in method is available in this build. Apple sign-in needs a
            development build, and Google needs both client IDs set.
          </Text>
        ) : null}

        <Text style={s.legal}>We only use your account to sign you in.</Text>
      </View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.void, justifyContent: "space-between" },

  head: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
  },
  dot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.ember },
  mark: { ...type.label, color: colors.inkDim },

  statement: { paddingHorizontal: spacing.lg, gap: spacing.md },
  headline: { ...type.hero, fontSize: 52, lineHeight: 52, color: colors.ink },
  sub: { ...type.body, color: colors.inkDim, lineHeight: 24, maxWidth: 300 },

  actions: { padding: spacing.lg, gap: spacing.sm },
  apple: { height: 54, width: "100%" },
  note: { ...type.small, color: colors.inkDim, lineHeight: 20, marginTop: spacing.sm },
  legal: {
    ...type.small,
    fontSize: 12,
    color: colors.inkFaint,
    textAlign: "center",
    marginTop: spacing.sm,
  },
});
