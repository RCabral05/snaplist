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

import { Avatar } from "@/components/avatar";
import { Field } from "@/components/field";
import { useAuth } from "@/lib/auth";
import { pickAvatar, type PickedAvatar } from "@/lib/avatar";
import { renameBrand, updateBrand, uploadBrandLogo, useBrands, type BrandPatch } from "@/lib/brands";
import { useGoBack } from "@/lib/navigation";
import { HANDLE_MAX, handleHint, useHandleCheck } from "@/lib/use-handle-check";
import { colors, spacing, type } from "@/theme";

const NAME_MAX = 40;
const BIO_MAX = 160;

/** Everything about the active brand: logo, name, handle, bio. */
export default function BrandSettingsScreen() {
  const { user } = useAuth();
  const { active, refresh } = useBrands();
  const goBack = useGoBack("/account");

  const [name, setName] = useState(active?.name ?? "");
  const [slug, setSlug] = useState(active?.slug ?? "");
  const [bio, setBio] = useState(active?.bio ?? "");
  const [picked, setPicked] = useState<PickedAvatar | null>(null);
  const [cleared, setCleared] = useState(false);
  const [saving, setSaving] = useState(false);

  const status = useHandleCheck(slug, "brand_slug_available", active?.slug);

  if (!user || !active) return null;

  const preview = picked
    ? `data:${picked.mime};base64,${picked.base64}`
    : cleared
      ? null
      : active.logo_url;

  const slugOk = status.kind === "available" || status.kind === "unchanged";
  const dirty =
    name.trim() !== active.name ||
    slug.trim() !== active.slug ||
    bio.trim() !== (active.bio ?? "") ||
    !!picked ||
    cleared;

  const tone =
    status.kind === "available"
      ? colors.success
      : status.kind === "taken" || status.kind === "invalid" || status.kind === "error"
        ? colors.danger
        : colors.textMuted;

  async function choose() {
    try {
      const next = await pickAvatar();
      if (!next) return;
      setPicked(next);
      setCleared(false);
    } catch (e: any) {
      Alert.alert("Could not open photos", e?.message ?? "Something went wrong.");
    }
  }

  async function save() {
    if (!user || !active) return;
    setSaving(true);
    try {
      // The handle first: it is the only write that can be refused, so a lost
      // race leaves nothing half-applied.
      if (slug.trim().toLowerCase() !== active.slug.toLowerCase()) {
        await renameBrand(active.id, slug.trim());
      }

      const patch: BrandPatch = {};
      if (name.trim() !== active.name) patch.name = name.trim();
      if (bio.trim() !== (active.bio ?? "")) patch.bio = bio.trim() || null;
      if (picked) patch.logo_url = await uploadBrandLogo(user.id, active.id, picked);
      else if (cleared) patch.logo_url = null;
      if (Object.keys(patch).length > 0) await updateBrand(active.id, patch);

      await refresh();
      goBack();
    } catch (e: any) {
      const raw = String(e?.message ?? "");
      Alert.alert(
        "Could not save",
        raw.includes("slug_taken")
          ? "Someone took that handle a moment ago. Try another."
          : raw.includes("invalid_slug")
            ? "That handle is not allowed."
            : raw || "Something went wrong.",
      );
    } finally {
      setSaving(false);
    }
  }

  function cancel() {
    if (!dirty) return goBack();
    Alert.alert("Discard changes?", "Your edits will not be saved.", [
      { text: "Keep editing", style: "cancel" },
      { text: "Discard", style: "destructive", onPress: goBack },
    ]);
  }

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.header}>
        <View style={s.side}>
          <Pressable onPress={cancel} hitSlop={12} disabled={saving}>
            <Text style={[s.action, saving && s.actionOff]}>Cancel</Text>
          </Pressable>
        </View>
        <Text style={s.headerTitle}>Brand</Text>
        <View style={[s.side, s.sideRight]}>
          <Pressable onPress={save} hitSlop={12} disabled={!dirty || !slugOk || saving}>
            {saving ? (
              <ActivityIndicator size="small" color={colors.ember} />
            ) : (
              <Text style={[s.action, s.save, (!dirty || !slugOk) && s.actionOff]}>Save</Text>
            )}
          </Pressable>
        </View>
      </View>

      <KeyboardAvoidingView style={s.flex} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
          <View style={s.logo}>
            <Pressable onPress={choose} disabled={saving}>
              <Avatar url={preview} name={name} handle={slug} size={96} />
            </Pressable>
            <View style={s.logoActions}>
              <Pressable onPress={choose} hitSlop={8} disabled={saving}>
                <Text style={s.link}>{preview ? "Change logo" : "Add logo"}</Text>
              </Pressable>
              {preview ? (
                <Pressable
                  onPress={() => {
                    setPicked(null);
                    setCleared(true);
                  }}
                  hitSlop={8}
                  disabled={saving}
                >
                  <Text style={[s.link, s.linkDanger]}>Remove</Text>
                </Pressable>
              ) : null}
            </View>
          </View>

          <Field label="Brand name" hint="Shown on your storefront and on every listing.">
            <TextInput
              value={name}
              onChangeText={setName}
              placeholder="Nike"
              placeholderTextColor={colors.inkFaint}
              maxLength={NAME_MAX}
              style={s.input}
              editable={!saving}
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
              editable={!saving}
            />
            {status.kind === "checking" ? (
              <ActivityIndicator size="small" color={colors.textFaint} />
            ) : null}
          </Field>

          <Field label="About" hint={`${bio.length}/${BIO_MAX}`}>
            <TextInput
              value={bio}
              onChangeText={setBio}
              placeholder="What this brand sells."
              placeholderTextColor={colors.inkFaint}
              maxLength={BIO_MAX}
              multiline
              style={[s.input, s.inputMulti]}
              editable={!saving}
            />
          </Field>

          <Text style={s.warning}>
            Changing the handle frees the old one for someone else, and links pointing at
            it stop working.
          </Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  flex: { flex: 1 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  side: { flex: 1 },
  sideRight: { alignItems: "flex-end" },
  headerTitle: { ...type.heading, color: colors.ink },
  action: { ...type.body, color: colors.inkDim },
  save: { ...type.bodyMedium, color: colors.ember },
  actionOff: { opacity: 0.35 },
  body: { padding: spacing.lg, gap: spacing.lg, paddingBottom: spacing.xxl },
  logo: { alignItems: "center", gap: spacing.sm },
  logoActions: { flexDirection: "row", gap: spacing.md },
  link: { ...type.small, color: colors.ember },
  linkDanger: { color: colors.danger },
  input: { ...type.body, color: colors.ink, flex: 1, paddingVertical: spacing.sm + 4 },
  inputMulti: { minHeight: 72, textAlignVertical: "top", paddingTop: spacing.sm + 4 },
  at: { ...type.body, color: colors.inkFaint },
  warning: { ...type.small, fontSize: 13, color: colors.textFaint, lineHeight: 19 },
});
