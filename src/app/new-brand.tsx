import { useRouter } from "expo-router";
import { useState } from "react";
import {
  ActivityIndicator,
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
import { Field } from "@/components/field";
import { Icon } from "@/components/icon";
import { useAuth } from "@/lib/auth";
import { createBrand, useBrands } from "@/lib/brands";
import { HANDLE_MAX, handleHint, useHandleCheck } from "@/lib/use-handle-check";
import { colors, spacing, type } from "@/theme";

const NAME_MAX = 40;

/**
 * Create a brand. This is onboarding for a new seller - there is no way into the
 * app without one - and the same screen reached from Account when they add
 * another. A brand, not a username: products hang off it today and events will
 * later, so the handle belongs to the storefront rather than to the person.
 */
export default function NewBrandScreen() {
  const router = useRouter();
  const { signOut } = useAuth();
  const { brands, refresh, setActive } = useBrands();

  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [busy, setBusy] = useState(false);

  const first = brands.length === 0;
  const status = useHandleCheck(slug, "brand_slug_available");

  const tone =
    status.kind === "available"
      ? colors.success
      : status.kind === "taken" || status.kind === "invalid" || status.kind === "error"
        ? colors.danger
        : colors.textMuted;

  async function create() {
    setBusy(true);
    try {
      const brand = await createBrand(slug, name);
      await refresh();
      setActive(brand.id);
      // The first brand lifts the routing guard on its own; a later one is a
      // push from Account and has somewhere to go back to.
      if (!first) router.back();
    } catch (e: any) {
      const raw = String(e?.message ?? "");
      Alert.alert(
        "Could not create that",
        raw.includes("slug_taken")
          ? "Someone took that handle a moment ago. Try another."
          : raw.includes("invalid_slug")
            ? "That handle is not allowed."
            : raw || "Something went wrong.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <SafeAreaView style={s.safe}>
      <KeyboardAvoidingView style={s.flex} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
          {!first ? (
            <Pressable onPress={() => router.back()} hitSlop={12} style={s.back}>
              <Icon name="chevron.left" size={18} color={colors.ink} weight="semibold" />
            </Pressable>
          ) : null}

          <View style={s.head}>
            <Text style={s.title}>{first ? "Name your brand" : "New brand"}</Text>
            <Text style={s.sub}>
              Everything you sell lives under a brand. Buyers find you by its handle, and
              you can run more than one.
            </Text>
          </View>

          <Field label="Brand name" hint="Shown on your storefront and on every listing.">
            <TextInput
              value={name}
              onChangeText={setName}
              placeholder="Nike"
              placeholderTextColor={colors.inkFaint}
              maxLength={NAME_MAX}
              style={s.input}
              editable={!busy}
            />
          </Field>

          <Field label="Handle" hint={handleHint(status, "handle")} hintTone={tone}>
            <Text style={s.at}>@</Text>
            <TextInput
              value={slug}
              onChangeText={setSlug}
              placeholder="nike"
              placeholderTextColor={colors.inkFaint}
              autoCapitalize="none"
              autoCorrect={false}
              maxLength={HANDLE_MAX}
              style={s.input}
              editable={!busy}
            />
            {status.kind === "checking" ? (
              <ActivityIndicator size="small" color={colors.textFaint} />
            ) : null}
          </Field>

          <Button
            label={first ? "Create brand" : "Add brand"}
            onPress={create}
            loading={busy}
            disabled={status.kind !== "available"}
            style={s.cta}
          />

          {first ? (
            <Button label="Sign out" variant="ghost" onPress={() => signOut().catch(() => {})} />
          ) : null}

          <Text style={s.note}>
            You can add a logo and change the name afterwards. The handle can change too,
            but links to the old one stop working.
          </Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  flex: { flex: 1 },
  body: { flexGrow: 1, justifyContent: "center", padding: spacing.lg, gap: spacing.md },
  back: { alignSelf: "flex-start", marginBottom: spacing.sm },
  head: { gap: spacing.xs, marginBottom: spacing.sm },
  title: { ...type.display, color: colors.ink },
  sub: { ...type.body, color: colors.textMuted, lineHeight: 22 },
  input: { ...type.body, color: colors.ink, flex: 1, paddingVertical: spacing.sm + 4 },
  at: { ...type.body, color: colors.inkFaint },
  cta: { marginTop: spacing.sm },
  note: { ...type.small, fontSize: 13, color: colors.textFaint, lineHeight: 19 },
});
