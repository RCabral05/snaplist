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

import { Avatar } from "@/components/avatar";
import { Field } from "@/components/field";
import { useAuth, type ProfilePatch } from "@/lib/auth";
import { clearAvatar, pickAvatar, uploadAvatar, type PickedAvatar } from "@/lib/avatar";
import { USERNAME_MAX, useUsernameCheck, usernameHint } from "@/lib/use-username-check";
import { colors, spacing, type } from "@/theme";

const DISPLAY_NAME_MAX = 40;

/**
 * Everything a seller can change about themselves, in one sheet. Nothing is
 * written until Save: the picked image is held in memory, so backing out costs
 * neither an upload nor an orphaned file in the bucket.
 */
export default function EditProfileScreen() {
  const router = useRouter();
  const { user, profile, updateProfile, claimUsername } = useAuth();

  const [name, setName] = useState(profile?.display_name ?? "");
  const [handle, setHandle] = useState(profile?.username ?? "");
  const [picked, setPicked] = useState<PickedAvatar | null>(null);
  const [cleared, setCleared] = useState(false);
  const [saving, setSaving] = useState(false);

  const status = useUsernameCheck(handle, profile?.username);

  if (!user || !profile) return null;

  const preview = picked
    ? `data:${picked.mime};base64,${picked.base64}`
    : cleared
      ? null
      : profile.avatar_url;

  const usernameOk = status.kind === "available" || status.kind === "unchanged";
  const dirty =
    name.trim() !== profile.display_name ||
    handle.trim() !== (profile.username ?? "") ||
    !!picked ||
    cleared;

  const tone =
    status.kind === "available"
      ? colors.success
      : status.kind === "taken" || status.kind === "invalid" || status.kind === "error"
        ? colors.danger
        : colors.textMuted;

  async function choosePhoto() {
    try {
      const next = await pickAvatar();
      if (!next) return;
      setPicked(next);
      setCleared(false);
    } catch (e: any) {
      Alert.alert("Could not open photos", e?.message ?? "Something went wrong.");
    }
  }

  function removePhoto() {
    setPicked(null);
    setCleared(true);
  }

  async function save() {
    if (!user || !profile) return;
    setSaving(true);
    try {
      // Username first. It is the only write here that can be refused, and
      // taking it before the others means a lost race leaves nothing
      // half-applied for the seller to puzzle over.
      const wanted = handle.trim();
      if (wanted.toLowerCase() !== (profile.username ?? "").toLowerCase()) {
        await claimUsername(wanted);
      }

      const patch: ProfilePatch = {};
      if (name.trim() !== profile.display_name) patch.display_name = name.trim();
      if (picked) {
        patch.avatar_url = await uploadAvatar(user.id, picked);
      } else if (cleared) {
        await clearAvatar(user.id);
        patch.avatar_url = null;
      }
      if (Object.keys(patch).length > 0) await updateProfile(patch);

      router.back();
    } catch (e: any) {
      const raw = String(e?.message ?? "");
      Alert.alert(
        "Could not save",
        raw.includes("username_taken")
          ? "Someone took that name a moment ago. Try another."
          : raw.includes("invalid_username")
            ? "That name is not allowed."
            : raw || "Something went wrong.",
      );
    } finally {
      setSaving(false);
    }
  }

  function cancel() {
    if (!dirty) return router.back();
    Alert.alert("Discard changes?", "Your edits will not be saved.", [
      { text: "Keep editing", style: "cancel" },
      { text: "Discard", style: "destructive", onPress: () => router.back() },
    ]);
  }

  return (
    <SafeAreaView style={s.safe}>
      {/* Three columns with the sides on equal flex, so the title is centred on
          the screen rather than on whatever is left between two labels of
          different widths. */}
      <View style={s.header}>
        <View style={s.side}>
          <Pressable onPress={cancel} hitSlop={12} disabled={saving}>
            <Text style={[s.action, saving && s.actionOff]}>Cancel</Text>
          </Pressable>
        </View>
        <Text style={s.headerTitle}>Edit profile</Text>
        <View style={[s.side, s.sideRight]}>
          <Pressable onPress={save} hitSlop={12} disabled={!dirty || !usernameOk || saving}>
            {saving ? (
              <ActivityIndicator size="small" color={colors.ember} />
            ) : (
              <Text style={[s.action, s.save, (!dirty || !usernameOk) && s.actionOff]}>Save</Text>
            )}
          </Pressable>
        </View>
      </View>

      <KeyboardAvoidingView
        style={s.flex}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
          <View style={s.photo}>
            <Pressable onPress={choosePhoto} disabled={saving}>
              <Avatar url={preview} name={name} handle={handle} size={96} />
            </Pressable>
            <View style={s.photoActions}>
              <Pressable onPress={choosePhoto} hitSlop={8} disabled={saving}>
                <Text style={s.link}>{preview ? "Change photo" : "Add photo"}</Text>
              </Pressable>
              {preview ? (
                <Pressable onPress={removePhoto} hitSlop={8} disabled={saving}>
                  <Text style={[s.link, s.linkDanger]}>Remove</Text>
                </Pressable>
              ) : null}
            </View>
          </View>

          <Field label="Display name" hint="The name buyers see on your listings.">
            <TextInput
              value={name}
              onChangeText={setName}
              placeholder="Your name"
              placeholderTextColor={colors.inkFaint}
              maxLength={DISPLAY_NAME_MAX}
              style={s.input}
              editable={!saving}
            />
          </Field>

          <Field label="Username" hint={usernameHint(status)} hintTone={tone}>
            <Text style={s.at}>@</Text>
            <TextInput
              value={handle}
              onChangeText={setHandle}
              placeholder="username"
              placeholderTextColor={colors.inkFaint}
              autoCapitalize="none"
              autoCorrect={false}
              maxLength={USERNAME_MAX}
              style={s.input}
              editable={!saving}
            />
            {status.kind === "checking" ? (
              <ActivityIndicator size="small" color={colors.textFaint} />
            ) : null}
          </Field>

          <Text style={s.warning}>
            Changing your username frees the old one for someone else, and links
            pointing at it stop working.
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
  photo: { alignItems: "center", gap: spacing.sm },
  photoActions: { flexDirection: "row", gap: spacing.md },
  link: { ...type.small, color: colors.ember },
  linkDanger: { color: colors.danger },
  input: { ...type.body, color: colors.ink, flex: 1, paddingVertical: spacing.sm + 4 },
  at: { ...type.body, color: colors.inkFaint },
  // A footnote, drawn as one. The filled grey block this used to be carried more
  // visual weight than the fields it was cautioning about.
  warning: { ...type.small, fontSize: 13, color: colors.textFaint, lineHeight: 19 },
});
