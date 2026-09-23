import * as AppleAuthentication from "expo-apple-authentication";
import { useState } from "react";
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { googleConfigured, useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

export default function SignInScreen() {
  const { signInWithApple, signInWithGoogle, signInWithEmail, signUpWithEmail } = useAuth();
  const [mode, setMode] = useState<"sign-in" | "sign-up">("sign-in");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    try {
      await fn();
    } catch (e: any) {
      Alert.alert("Could not sign in", e?.message ?? "Something went wrong.");
    } finally {
      setBusy(false);
    }
  };

  const submit = () =>
    run(async () => {
      if (mode === "sign-in") {
        await signInWithEmail(email, password);
        return;
      }
      const { needsConfirmation } = await signUpWithEmail(email, password);
      if (needsConfirmation) {
        Alert.alert("Check your email", "Confirm the address, then sign in.");
        setMode("sign-in");
      }
    });

  return (
    <SafeAreaView style={s.safe}>
      <KeyboardAvoidingView
        style={s.flex}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
          <View style={s.brand}>
            <Text style={s.wordmark}>Snaplist</Text>
            <Text style={s.tagline}>Snap it once. List it everywhere.</Text>
          </View>

          {/* Apple first: it is the flow most people will take, and offering
              other third-party sign-in without it fails App Review. */}
          <AppleAuthentication.AppleAuthenticationButton
            buttonType={AppleAuthentication.AppleAuthenticationButtonType.SIGN_IN}
            buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.BLACK}
            cornerRadius={radius.md}
            style={s.apple}
            onPress={() => run(signInWithApple)}
          />

          {googleConfigured ? (
            <Button
              label="Continue with Google"
              variant="secondary"
              onPress={() => run(signInWithGoogle)}
              style={s.google}
            />
          ) : null}

          <View style={s.dividerRow}>
            <View style={s.rule} />
            <Text style={s.dividerText}>or</Text>
            <View style={s.rule} />
          </View>

          <TextInput
            value={email}
            onChangeText={setEmail}
            placeholder="Email"
            placeholderTextColor={colors.inkFaint}
            autoCapitalize="none"
            autoComplete="email"
            keyboardType="email-address"
            style={s.input}
          />
          <TextInput
            value={password}
            onChangeText={setPassword}
            placeholder="Password"
            placeholderTextColor={colors.inkFaint}
            autoCapitalize="none"
            autoComplete={mode === "sign-in" ? "current-password" : "new-password"}
            secureTextEntry
            style={s.input}
            onSubmitEditing={submit}
          />

          <Button
            label={mode === "sign-in" ? "Sign in" : "Create account"}
            onPress={submit}
            loading={busy}
            disabled={!email.trim() || password.length < 6}
          />

          <Pressable onPress={() => setMode(mode === "sign-in" ? "sign-up" : "sign-in")}>
            <Text style={s.switch}>
              {mode === "sign-in"
                ? "No account yet? Create one"
                : "Already have an account? Sign in"}
            </Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  flex: { flex: 1 },
  body: { flexGrow: 1, justifyContent: "center", padding: spacing.lg, gap: spacing.sm },
  brand: { marginBottom: spacing.lg, gap: spacing.xs },
  wordmark: { ...type.display, fontSize: 40, color: colors.ink },
  tagline: { ...type.body, color: colors.textMuted },
  apple: { height: 52, width: "100%" },
  google: { marginTop: spacing.sm },
  dividerRow: { flexDirection: "row", alignItems: "center", gap: spacing.sm, marginVertical: spacing.sm },
  rule: { flex: 1, height: 1, backgroundColor: colors.border },
  dividerText: { ...type.small, color: colors.textFaint },
  input: {
    ...type.body,
    color: colors.ink,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 4,
  },
  switch: { ...type.small, color: colors.textMuted, textAlign: "center", paddingVertical: spacing.md },
});
