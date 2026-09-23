import { Image } from "expo-image";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useEffect, useMemo, useState } from "react";
import { Alert, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { ChannelRow } from "@/components/channel-row";
import { useConnections } from "@/lib/connections";
import { getDraft, money, parseMoney, publish, putDraft, removeDraft } from "@/lib/listings";
import { adapters, canPublish, validateDraft, type ChannelId, type ListingDraft } from "@/lib/marketplaces";
import { colors, radius, spacing, type } from "@/theme";

export default function DraftScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { isConnected } = useConnections();

  const [draft, setDraft] = useState<ListingDraft | null>(null);
  const [price, setPrice] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    // Poll briefly: the suggestion from the camera screen lands after this mounts.
    const tick = () =>
      getDraft(id).then((d) => {
        if (!alive || !d) return;
        setDraft((prev) => (prev && prev.updatedAt === d.updatedAt ? prev : d));
        setPrice((p) => (p ? p : d.priceCents ? String(d.priceCents / 100) : ""));
      });
    tick();
    const timer = setInterval(tick, 700);
    const stop = setTimeout(() => clearInterval(timer), 8000);
    return () => {
      alive = false;
      clearInterval(timer);
      clearTimeout(stop);
    };
  }, [id]);

  const issues = useMemo(() => (draft ? validateDraft(draft) : []), [draft]);
  const ready = draft ? canPublish(draft) : false;

  if (!draft) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.center}>
          <Text style={s.muted}>Loading draft…</Text>
        </View>
      </SafeAreaView>
    );
  }

  const set = (patch: Partial<ListingDraft>) => {
    const next = { ...draft, ...patch };
    setDraft(next);
    putDraft(next);
  };

  const toggleChannel = (channel: ChannelId) => {
    const on = draft.channels.includes(channel);
    set({
      channels: on
        ? draft.channels.filter((c) => c !== channel)
        : [...draft.channels, channel],
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
          live ? live + " channel(s) live." : null,
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

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
        {draft.photos[0] ? (
          <Image source={{ uri: draft.photos[0] }} style={s.hero} contentFit="cover" />
        ) : null}

        <Text style={s.label}>Title</Text>
        <TextInput
          value={draft.title}
          onChangeText={(t) => set({ title: t })}
          placeholder="What is it?"
          placeholderTextColor={colors.inkFaint}
          style={s.input}
        />

        <Text style={s.label}>Price</Text>
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
        {draft.priceCents > 0 ? (
          <Text style={s.hint}>Listing at {money(draft.priceCents, draft.currency)}</Text>
        ) : null}

        <Text style={s.label}>Description</Text>
        <TextInput
          value={draft.description}
          onChangeText={(t) => set({ description: t })}
          placeholder="Condition, size, flaws, anything a buyer would ask."
          placeholderTextColor={colors.inkFaint}
          multiline
          style={[s.input, s.inputMulti]}
        />

        <View style={s.row}>
          <View style={s.rowItem}>
            <Text style={s.label}>Brand</Text>
            <TextInput
              value={draft.brand ?? ""}
              onChangeText={(t) => set({ brand: t || undefined })}
              placeholder="Optional"
              placeholderTextColor={colors.inkFaint}
              style={s.input}
            />
          </View>
          <View style={s.rowItem}>
            <Text style={s.label}>Category</Text>
            <TextInput
              value={draft.category ?? ""}
              onChangeText={(t) => set({ category: t || undefined })}
              placeholder="Optional"
              placeholderTextColor={colors.inkFaint}
              style={s.input}
            />
          </View>
        </View>

        <Text style={s.section}>Post to</Text>
        {adapters.map((adapter) => {
          const connected = isConnected(adapter.id);
          const selected = draft.channels.includes(adapter.id);
          const firstError = issues.find(
            (i) => i.channel === adapter.id && i.severity === "error",
          );
          return (
            <ChannelRow
              key={adapter.id}
              adapter={adapter}
              selected={selected}
              connected={connected}
              issue={selected ? firstError?.message : undefined}
              onPress={() => toggleChannel(adapter.id)}
            />
          );
        })}

        <Button
          label={"Publish to " + draft.channels.length + " channel(s)"}
          onPress={onPublish}
          disabled={!ready || !draft.channels.length}
          loading={busy}
          style={{ marginTop: spacing.md }}
        />
        <Button
          label="Delete draft"
          variant="ghost"
          onPress={() =>
            Alert.alert("Delete this draft?", "This cannot be undone.", [
              { text: "Cancel", style: "cancel" },
              {
                text: "Delete",
                style: "destructive",
                onPress: async () => {
                  await removeDraft(draft.id);
                  router.back();
                },
              },
            ])
          }
        />
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  muted: { ...type.body, color: colors.textMuted },
  body: { padding: spacing.md, gap: spacing.sm, paddingBottom: spacing.xxl },
  hero: { width: "100%", aspectRatio: 1, borderRadius: radius.lg, backgroundColor: colors.surfaceHigh },
  label: { ...type.label, color: colors.textMuted, marginTop: spacing.sm },
  section: { ...type.label, color: colors.textMuted, marginTop: spacing.lg },
  input: {
    ...type.body,
    color: colors.ink,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    backgroundColor: colors.paper,
  },
  inputMulti: { minHeight: 96, textAlignVertical: "top" },
  hint: { ...type.small, color: colors.textMuted },
  row: { flexDirection: "row", gap: spacing.sm },
  rowItem: { flex: 1 },
});
