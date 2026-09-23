import { useState } from "react";
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { useAuth } from "@/lib/auth";
import { USERNAME_MAX, useUsernameCheck, usernameHint } from "@/lib/use-username-check";
import { colors, radius, spacing, type } from "@/theme";

/**
 * Shown once, between signing in and reaching the app: a seller needs a name
 * before they can have a storefront. There is no skip - every later screen can
 * then assume profile.username exists.
 */
export default function UsernameScreen() {
  const { claimUsername, signOut } = useAuth();
  const [value, setValue] = useState("");
  const [busy, setBusy] = useState(false);
  const status = useUsernameCheck(value);

  const tone =
    status.kind === "available"
      ? colors.success
      : status.kind === "taken" || status.kind === "invalid" || status.kind === "error"
        ? colors.danger
        : colors.textMuted;

  async function claim() {
    setBusy(true);
    try {
      await claimUsername(value.trim());
      // No navigation here: the root layout routes on profile.username, which
      // claimUsername refreshes. One source of truth for where the user belongs.
    } catch (e: any) {
      const raw = String(e?.message ?? "");
      Alert.alert(
        "Could not claim that",
        raw.includes("username_taken")
          ? "Someone took it a moment ago. Try another."
          : raw.includes("invalid_username")
            ? "That name is not allowed."
            : raw || "Something went wrong.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <SafeAreaView style={s.safe}>
      <KeyboardAvoidingView
        style={s.flex}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <View style={s.body}>
          <View style={s.head}>
            <Text style={s.title}>Pick a username</Text>
            <Text style={s.sub}>
              This is how buyers find you. You can change it later, but links to your old name
              will stop working.
            </Text>
          </View>

          <View style={s.fieldRow}>
            <Text style={s.at}>@</Text>
            <TextInput
              value={value}
              onChangeText={setValue}
              placeholder="username"
              placeholderTextColor={colors.inkFaint}
              autoCapitalize="none"
              autoCorrect={false}
              autoFocus
              maxLength={USERNAME_MAX}
              style={s.input}
              onSubmitEditing={status.kind === "available" ? claim : undefined}
            />
            {status.kind === "checking" ? (
              <ActivityIndicator size="small" color={colors.textFaint} />
            ) : null}
          </View>

          <Text style={[s.hint, { color: tone }]}>{usernameHint(status)}</Text>

          <Button
            label="Continue"
            onPress={claim}
            loading={busy}
            disabled={status.kind !== "available"}
            style={{ marginTop: spacing.md }}
          />

          <Button label="Sign out" variant="ghost" onPress={() => signOut().catch(() => {})} />
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  flex: { flex: 1 },
  body: { flex: 1, justifyContent: "center", padding: spacing.lg, gap: spacing.sm },
  head: { gap: spacing.xs, marginBottom: spacing.md },
  title: { ...type.display, color: colors.ink },
  sub: { ...type.body, color: colors.textMuted, lineHeight: 22 },
  fieldRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.xs,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
  },
  at: { ...type.title, color: colors.inkFaint },
  input: { ...type.title, color: colors.ink, flex: 1, paddingVertical: spacing.sm + 4 },
  hint: { ...type.small, paddingHorizontal: spacing.xs },
});
