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
import { clearAvatar, pickAvatar, uploadAvatar, type PickedImage } from "@/lib/avatar";
import { useGoBack } from "@/lib/navigation";
import { colors, spacing, type } from "@/theme";

const DISPLAY_NAME_MAX = 40;

/**
 * Your photo and your name. Nothing here is public.
 *
 * Nothing is written until Save, so backing out costs neither an upload nor an
 * orphaned object in the bucket.
 */
export default function EditProfileScreen() {
  const { user, profile, updateProfile } = useAuth();
  const goBack = useGoBack("/");

  const [name, setName] = useState(profile?.display_name ?? "");
  const [picked, setPicked] = useState<PickedImage | null>(null);
  const [cleared, setCleared] = useState(false);
  const [saving, setSaving] = useState(false);

  if (!user || !profile) return null;

  const preview = picked
    ? `data:${picked.mime};base64,${picked.base64}`
    : cleared
      ? null
      : profile.avatar_url;

  const dirty = name.trim() !== profile.display_name || !!picked || cleared;

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

  async function save() {
    if (!user || !profile) return;
    setSaving(true);
    try {
      const patch: ProfilePatch = {};
      if (name.trim() !== profile.display_name) patch.display_name = name.trim();
      if (picked) {
        patch.avatar_url = await uploadAvatar(user.id, picked);
      } else if (cleared) {
        await clearAvatar(user.id);
        patch.avatar_url = null;
      }
      if (Object.keys(patch).length > 0) await updateProfile(patch);

      goBack();
    } catch (e: any) {
      Alert.alert("Could not save", e?.message ?? "Something went wrong.");
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
        <Text style={s.headerTitle}>Your profile</Text>
        <View style={[s.side, s.sideRight]}>
          <Pressable onPress={save} hitSlop={12} disabled={!dirty || saving}>
            {saving ? (
              <ActivityIndicator size="small" color={colors.ember} />
            ) : (
              <Text style={[s.action, s.save, !dirty && s.actionOff]}>Save</Text>
            )}
          </Pressable>
        </View>
      </View>

      <KeyboardAvoidingView style={s.flex} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
          <View style={s.photo}>
            <Pressable onPress={choosePhoto} disabled={saving}>
              <Avatar url={preview} name={name} size={96} />
            </Pressable>
            <View style={s.photoActions}>
              <Pressable onPress={choosePhoto} hitSlop={8} disabled={saving}>
                <Text style={s.link}>{preview ? "Change photo" : "Add photo"}</Text>
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

          <Field label="Your name" hint="Shown on your profile.">
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
});
