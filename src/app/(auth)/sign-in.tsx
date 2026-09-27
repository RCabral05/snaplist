import * as AppleAuthentication from "expo-apple-authentication";
import { useEffect, useState } from "react";
import { Alert, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { googleConfigured, useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

/**
 * One sentence, set large, and two ways in.
 *
 * A sign-in screen is the only place the app gets to say what it is before
 * anyone has seen it, so it says so in the same serif the app itself uses
 * rather than with a logo and a tagline in grey.
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
      <View style={s.top} />

      <View style={s.statement}>
        <Text style={s.headline}>Snaplist</Text>
        <Text style={s.sub}>Sign in to pick up where you left off.</Text>
      </View>

      <View style={s.actions}>
        {appleReady ? (
          <AppleAuthentication.AppleAuthenticationButton
            buttonType={AppleAuthentication.AppleAuthenticationButtonType.CONTINUE}
            buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.BLACK}
            cornerRadius={radius.pill}
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
  safe: { flex: 1, backgroundColor: colors.paper, justifyContent: "space-between" },
  top: { paddingHorizontal: spacing.lg, paddingTop: spacing.lg },
  mark: { ...type.label, color: colors.ember },
  statement: { paddingHorizontal: spacing.lg, gap: spacing.md },
  headline: { ...type.hero, fontSize: 42, lineHeight: 46, color: colors.ink },
  sub: { ...type.body, color: colors.textMuted, lineHeight: 24, maxWidth: 320 },
  actions: { padding: spacing.lg, gap: spacing.sm },
  apple: { height: 54, width: "100%" },
  note: { ...type.small, color: colors.textMuted, lineHeight: 20, marginTop: spacing.sm },
  legal: {
    ...type.small,
    fontSize: 12,
    color: colors.inkFaint,
    textAlign: "center",
    marginTop: spacing.sm,
  },
});
