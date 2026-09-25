import { Image } from "expo-image";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { ChannelRow } from "@/components/channel-row";
import { Field } from "@/components/field";
import { Icon } from "@/components/icon";
import { PhotoStrip } from "@/components/photo-strip";
import { SectionLabel } from "@/components/screen";
import { useAuth } from "@/lib/auth";
import { CATEGORIES } from "@/lib/categories";
import { useConnections } from "@/lib/connections";
import { getDraft, money, parseMoney, publish, putDraft, removeDraft } from "@/lib/listings";
import { useGoBack } from "@/lib/navigation";
import {
  MAX_PHOTOS,
  pickListingPhoto,
  removeListingPhoto,
  uploadListingPhoto,
  usePhotoUrl,
} from "@/lib/photos";
import { useIsSuggesting } from "@/lib/suggesting";
import {
  adapters,
  canPublish,
  validateDraft,
  type ChannelId,
  type ListingDraft,
} from "@/lib/marketplaces";
import { colors, radius, spacing, type } from "@/theme";

const plural = (n: number, one: string) => `${n} ${one}${n === 1 ? "" : "s"}`;

/** Below this, the suggestion is a guess worth flagging rather than a recognition. */
const UNSURE_BELOW = 0.6;

export default function DraftScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuth();
  const { isConnected } = useConnections();

  const [draft, setDraft] = useState<ListingDraft | null>(null);
  const [price, setPrice] = useState("");
  const [busy, setBusy] = useState(false);
  const [adding, setAdding] = useState(false);

  const suggesting = useIsSuggesting(id);
  const goBack = useGoBack("/listings");

  useEffect(() => {
    let alive = true;
    // The suggestion is written by the camera screen's timeline, not this one, so
    // the editor watches for it. Polling is tied to whether that work is actually
    // running rather than to a fixed window - the old eight seconds was a guess
    // made before there was a model call behind it, and a slow one landed after
    // the screen had stopped looking.
    const tick = () =>
      getDraft(id).then((d) => {
        if (!alive || !d) return;
        setDraft((prev) => (prev && prev.updatedAt === d.updatedAt ? prev : d));
        setPrice((p) => (p ? p : d.priceCents ? String(d.priceCents / 100) : ""));
      });

    tick();
    if (!suggesting) return () => {
      alive = false;
    };

    const timer = setInterval(tick, 700);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, [id, suggesting]);

  const issues = useMemo(() => (draft ? validateDraft(draft) : []), [draft]);
  const ready = draft ? canPublish(draft) : false;
  // Called before the early return below so the hook order stays stable while
  // the draft is still loading.
  const heroUrl = usePhotoUrl(draft?.photos?.[0]);

  const header = (
    <View style={s.header}>
      <Pressable onPress={goBack} hitSlop={12} style={s.back}>
        <Icon name="chevron.left" size={18} color={colors.ink} weight="semibold" />
      </Pressable>
      <Text style={s.headerTitle}>Edit listing</Text>
      <View style={s.back} />
    </View>
  );

  if (!draft) {
    return (
      <SafeAreaView style={s.safe} edges={["top"]}>
        {header}
        <View style={s.center}>
          <Text style={s.muted}>Loading draft…</Text>
        </View>
      </SafeAreaView>
    );
  }

  const unsure =
    draft.suggestedConfidence !== undefined && draft.suggestedConfidence < UNSURE_BELOW;

  const set = (patch: Partial<ListingDraft>) => {
    const next = { ...draft, ...patch };
    // Touching the title is the seller saying they have read it, so the caveat
    // has done its job and should stop nagging.
    if (patch.title !== undefined) next.suggestedConfidence = undefined;
    setDraft(next);
    putDraft(next);
  };

  function addPhoto() {
    Alert.alert("Add a photo", undefined, [
      { text: "Take one", onPress: () => addFrom("camera") },
      { text: "Choose from library", onPress: () => addFrom("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  }

  async function addFrom(source: "camera" | "library") {
    if (!draft || !user) return;
    setAdding(true);
    try {
      const picked = await pickListingPhoto(source);
      if (!picked) return;
      const path = await uploadListingPhoto(user.id, draft.id, picked.base64, picked.mime);
      set({ photos: [...draft.photos, path] });
    } catch (e: any) {
      Alert.alert("Could not add that photo", e?.message ?? "Something went wrong.");
    } finally {
      setAdding(false);
    }
  }

  /**
   * Tapping a thumbnail. An Alert rather than a long-press menu: two actions do
   * not justify a gesture nobody discovers.
   */
  function photoActions(index: number) {
    if (!draft) return;
    const photo = draft.photos[index];
    const rest = draft.photos.filter((_, i) => i !== index);

    Alert.alert(
      index === 0 ? "Cover photo" : "Photo " + (index + 1),
      undefined,
      [
        ...(index === 0
          ? []
          : [
              {
                text: "Make cover",
                onPress: () => set({ photos: [photo, ...rest] }),
              },
            ]),
        {
          text: "Remove",
          style: "destructive" as const,
          onPress: () => {
            // The row first: an orphaned object is untidy, a listing pointing at
            // a deleted object is a broken image.
            set({ photos: rest });
            removeListingPhoto(photo).catch(() => {});
          },
        },
        { text: "Cancel", style: "cancel" as const },
      ],
    );
  }

  const toggleChannel = (channel: ChannelId) => {
    const on = draft.channels.includes(channel);
    set({
      channels: on ? draft.channels.filter((c) => c !== channel) : [...draft.channels, channel],
    });
  };

  async function onPublish() {
    if (!draft) return;
    setBusy(true);
    try {
      const results = await publish(draft);
      const live = results.filter((r) => r.state === "live").length;
      const failed = results.filter((r) => r.state === "failed");
      Alert.alert(
        failed.length ? "Published with problems" : "Published",
        [
          live ? plural(live, "channel") + " live." : null,
          ...failed.map((f) => f.channel + ": " + (f.message ?? "failed")),
        ]
          .filter(Boolean)
          .join("\n") || "Queued.",
      );
      router.replace("/listings");
    } finally {
      setBusy(false);
    }
  }

  function confirmDelete() {
    if (!draft) return;
    Alert.alert("Delete this draft?", "This cannot be undone.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: async () => {
          await removeDraft(draft.id);
          goBack();
        },
      },
    ]);
  }

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      {header}
      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
        {heroUrl ? (
          <View>
            <Image source={{ uri: heroUrl }} style={s.hero} contentFit="cover" />
            {suggesting ? (
              <View style={s.reading}>
                <View style={s.readingPill}>
                  <ActivityIndicator size="small" color={colors.white} />
                  <Text style={s.readingText}>Reading the photo…</Text>
                </View>
              </View>
            ) : null}
          </View>
        ) : null}

        <PhotoStrip
          photos={draft.photos}
          busy={adding}
          canAdd={draft.photos.length < MAX_PHOTOS}
          onAdd={addPhoto}
          onSelect={photoActions}
        />
        <Text style={s.photoHint}>
          {draft.photos.length === 1
            ? "One angle is rarely enough. Add a few more."
            : `${draft.photos.length} of ${MAX_PHOTOS} photos. The cover is what buyers see first.`}
        </Text>

        {unsure ? (
          <View style={s.unsure}>
            <Icon name="exclamationmark.triangle" size={15} color={colors.pending} />
            <Text style={s.unsureText}>
              Snaplist was not confident about this one. Check the title and the price
              before you publish.
            </Text>
          </View>
        ) : null}

        <Field label="Title">
          <TextInput
            value={draft.title}
            onChangeText={(t) => set({ title: t })}
            placeholder="What is it?"
            placeholderTextColor={colors.inkFaint}
            style={s.input}
          />
        </Field>

        <Field
          label="Price"
          hint={draft.priceCents > 0 ? `Listing at ${money(draft.priceCents, draft.currency)}` : undefined}
        >
          <Text style={s.currency}>$</Text>
          <TextInput
            value={price}
            onChangeText={(t) => {
              setPrice(t);
              set({ priceCents: parseMoney(t) });
            }}
            keyboardType="decimal-pad"
            placeholder="0.00"
            placeholderTextColor={colors.inkFaint}
            style={s.input}
          />
        </Field>

        <Field label="Description">
          <TextInput
            value={draft.description}
            onChangeText={(t) => set({ description: t })}
            placeholder="Condition, size, flaws, anything a buyer would ask."
            placeholderTextColor={colors.inkFaint}
            multiline
            style={[s.input, s.inputMulti]}
          />
        </Field>

        <View style={s.row}>
          <View style={s.rowItem}>
            <Field label="Brand">
              <TextInput
                value={draft.brand ?? ""}
                onChangeText={(t) => set({ brand: t || undefined })}
                placeholder="Optional"
                placeholderTextColor={colors.inkFaint}
                style={s.input}
              />
            </Field>
          </View>
        </View>

        {/* A picker, not a text field. Free text gave four listings four
            different categories and nothing to filter Shop by. */}
        <View style={s.group}>
          <SectionLabel>Category</SectionLabel>
          <View style={s.cats}>
            {CATEGORIES.map((c) => {
              const on = draft.categorySlug === c.slug;
              return (
                <Pressable
                  key={c.slug}
                  onPress={() => set({ categorySlug: on ? undefined : c.slug })}
                  style={[s.cat, on && s.catOn]}
                >
                  <Icon name={c.icon} size={13} color={on ? colors.white : colors.inkDim} />
                  <Text style={[s.catText, on && s.catTextOn]}>{c.label}</Text>
                </Pressable>
              );
            })}
          </View>
        </View>

        <View style={s.channels}>
          <SectionLabel>Post to</SectionLabel>
          {adapters.map((adapter) => {
            const selected = draft.channels.includes(adapter.id);
            const firstError = issues.find(
              (i) => i.channel === adapter.id && i.severity === "error",
            );
            return (
              <ChannelRow
                key={adapter.id}
                adapter={adapter}
                selected={selected}
                connected={isConnected(adapter.id)}
                issue={selected ? firstError?.message : undefined}
                onPress={() => toggleChannel(adapter.id)}
              />
            );
          })}
        </View>

        <Button
          label={
            draft.channels.length
              ? "Publish to " + plural(draft.channels.length, "channel")
              : "Pick a channel to publish to"
          }
          onPress={onPublish}
          disabled={!ready || !draft.channels.length}
          loading={busy}
          style={s.publish}
        />

        <Pressable onPress={confirmDelete} style={({ pressed }) => [s.delete, pressed && s.pressed]}>
          <Text style={s.deleteText}>Delete draft</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  pressed: { opacity: 0.6 },

  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  // Equal-width sides keep the title centred on the screen, not on the space
  // left over beside the back arrow.
  back: { width: 32 },
  headerTitle: { ...type.heading, color: colors.ink, flex: 1, textAlign: "center" },

  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  muted: { ...type.body, color: colors.textMuted },

  body: { padding: spacing.lg, gap: spacing.md, paddingBottom: spacing.xxl },
  hero: {
    width: "100%",
    aspectRatio: 1,
    borderRadius: radius.lg,
    backgroundColor: colors.surface,
  },
  // Over the photograph rather than beside it: the photo is the thing being
  // read, and an empty title field is not obviously busy.
  reading: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "rgba(22,24,29,0.35)",
    borderRadius: radius.lg,
  },
  readingPill: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radius.pill,
    backgroundColor: "rgba(22,24,29,0.85)",
  },
  readingText: { ...type.small, color: colors.white },
  input: { ...type.body, color: colors.ink, flex: 1, paddingVertical: spacing.sm + 4 },
  inputMulti: { minHeight: 96, textAlignVertical: "top", paddingTop: spacing.sm + 4 },
  currency: { ...type.body, color: colors.inkFaint },
  photoHint: { ...type.small, fontSize: 13, color: colors.inkFaint, marginTop: -spacing.xs },
  group: { gap: spacing.sm },
  cats: { flexDirection: "row", flexWrap: "wrap", gap: spacing.xs },
  cat: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: 9,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.rule,
  },
  catOn: { backgroundColor: colors.ink, borderColor: colors.ink },
  catText: { ...type.label, fontSize: 10, color: colors.inkDim },
  catTextOn: { color: colors.white },
  unsure: {
    flexDirection: "row",
    alignItems: "flex-start",
    gap: spacing.sm,
    padding: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: "rgba(192,120,0,0.35)",
    backgroundColor: "rgba(192,120,0,0.07)",
  },
  unsureText: { ...type.small, fontSize: 13, color: colors.inkDim, lineHeight: 19, flex: 1 },
  row: { flexDirection: "row", gap: spacing.sm },
  rowItem: { flex: 1 },
  channels: { gap: spacing.sm, marginTop: spacing.xs },
  publish: { marginTop: spacing.sm },
  delete: { alignItems: "center", paddingVertical: spacing.md },
  deleteText: { ...type.body, color: colors.danger },
});
