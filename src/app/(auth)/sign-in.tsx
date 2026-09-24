import * as AppleAuthentication from "expo-apple-authentication";
import { useEffect, useState } from "react";
import { Alert, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import { googleConfigured, useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

export default function SignInScreen() {
  const { signInWithApple, signInWithGoogle } = useAuth();
  const [busy, setBusy] = useState<"apple" | "google" | null>(null);
  // null while we ask. Rendering the Apple button when its native view is not in
  // the binary (Expo Go, or a dev client built before the package was added)
  // paints a red "Unimplemented component" box, so ask first.
  const [appleReady, setAppleReady] = useState<boolean | null>(null);

  useEffect(() => {
    let alive = true;
    AppleAuthentication.isAvailableAsync()
      .catch(() => false) // module missing entirely: the call itself throws
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
      {/* Brand in the upper third, actions at the bottom where a thumb is -
          the middle is deliberately empty rather than padded with filler. */}
      <View style={s.brand}>
        <View style={s.mark}>
          <Icon name="camera.viewfinder" size={30} color={colors.white} />
        </View>
        <Text style={s.wordmark}>Snaplist</Text>
        <Text style={s.tagline}>Snap it once. List it everywhere.</Text>
      </View>

      <View style={s.actions}>
        {appleReady ? (
          <AppleAuthentication.AppleAuthenticationButton
            buttonType={AppleAuthentication.AppleAuthenticationButtonType.CONTINUE}
            buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.BLACK}
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
            development build (Expo Go cannot load it), and Google needs both
            client IDs set.
          </Text>
        ) : null}

        <Text style={s.legal}>
          Snaplist only ever posts listings you publish yourself.
        </Text>
      </View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper, justifyContent: "space-between" },
  brand: { paddingHorizontal: spacing.lg, paddingTop: spacing.xxl, gap: spacing.sm },
  mark: {
    width: 60,
    height: 60,
    borderRadius: radius.lg,
    backgroundColor: colors.ember,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: spacing.md,
  },
  wordmark: { ...type.display, fontSize: 40, color: colors.ink },
  tagline: { ...type.body, color: colors.textMuted },
  actions: { padding: spacing.lg, gap: spacing.sm },
  apple: { height: 52, width: "100%" },
  note: { ...type.small, color: colors.textMuted, lineHeight: 20, marginTop: spacing.sm },
  legal: {
    ...type.small,
    fontSize: 12,
    color: colors.textFaint,
    textAlign: "center",
    marginTop: spacing.sm,
  },
});
