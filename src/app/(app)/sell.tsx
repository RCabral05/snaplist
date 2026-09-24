import { CameraView, useCameraPermissions } from "expo-camera";
import { useRouter } from "expo-router";
import { useRef, useState } from "react";
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { useAuth } from "@/lib/auth";
import { useBrands } from "@/lib/brands";
import { emptyDraft, putDraft } from "@/lib/listings";
import { uploadListingPhoto } from "@/lib/photos";
import { suggestFromPhoto } from "@/lib/vision";
import { colors, radius, spacing, type } from "@/theme";

/**
 * The whole product in one screen: shutter, then the draft is already filled in by
 * the time the editor opens. We create and persist the draft before the model call
 * returns, so a slow or failed suggestion costs the seller a photo, not the listing.
 */
export default function SellScreen() {
  const router = useRouter();
  const camera = useRef<CameraView>(null);
  const { user } = useAuth();
  const { active } = useBrands();
  const [permission, requestPermission] = useCameraPermissions();
  const [busy, setBusy] = useState(false);

  if (!permission) return <View style={s.safe} />;

  if (!permission.granted) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.gate}>
          <Text style={s.gateTitle}>Camera access</Text>
          <Text style={s.gateBody}>
            Snaplist needs the camera to photograph what you are selling.
          </Text>
          <Button label="Allow camera" onPress={requestPermission} />
        </View>
      </SafeAreaView>
    );
  }

  async function capture() {
    if (busy) return;
    setBusy(true);
    try {
      const photo = await camera.current?.takePictureAsync({ quality: 0.8, base64: true });
      if (!photo?.uri) return;

      if (!active) return; // the routing guard means there is always a brand

      // The row is created with the local file:// URI so the editor opens on the
      // photograph instead of a placeholder. That URI means nothing on another
      // device, which is exactly why it is replaced by the Storage path below as
      // soon as the upload lands - usually before the seller has typed a title.
      const draft = await putDraft(emptyDraft(active.id, [photo.uri]));
      router.push({ pathname: "/draft/[id]", params: { id: draft.id } });

      const [uploaded, suggestion] = await Promise.all([
        user && photo.base64
          ? uploadListingPhoto(user.id, draft.id, photo.base64).catch(() => null)
          : Promise.resolve(null),
        suggestFromPhoto(photo.uri).catch(() => null),
      ]);

      if (uploaded || suggestion) {
        await putDraft({
          ...draft,
          ...(uploaded ? { photos: [uploaded] } : {}),
          ...(suggestion
            ? {
                title: suggestion.title,
                description: suggestion.description,
                category: suggestion.category,
                brand: suggestion.brand,
                condition: suggestion.condition,
                priceCents: suggestion.priceCents,
              }
            : {}),
        });
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={s.safe}>
      <CameraView ref={camera} style={StyleSheet.absoluteFill} facing="back" />
      <SafeAreaView style={s.overlay} edges={["top", "bottom"]}>
        <View style={s.hint}>
          <Text style={s.hintText}>Fill the frame with the item</Text>
        </View>
        <View style={s.shutterRow}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Take photo"
            onPress={capture}
            disabled={busy}
            style={s.shutterRing}
          >
            {busy ? (
              <ActivityIndicator color={colors.white} />
            ) : (
              <View style={s.shutter} />
            )}
          </Pressable>
        </View>
      </SafeAreaView>
    </View>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.ink },
  overlay: { flex: 1, justifyContent: "space-between" },
  hint: { alignItems: "center", paddingTop: spacing.lg },
  hintText: {
    ...type.small,
    color: colors.white,
    backgroundColor: "rgba(0,0,0,0.45)",
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
    borderRadius: radius.pill,
    overflow: "hidden",
  },
  shutterRow: { alignItems: "center", paddingBottom: spacing.xl },
  shutterRing: {
    width: 78,
    height: 78,
    borderRadius: 39,
    borderWidth: 4,
    borderColor: colors.white,
    alignItems: "center",
    justifyContent: "center",
  },
  shutter: { width: 62, height: 62, borderRadius: 31, backgroundColor: colors.white },
  gate: { flex: 1, justifyContent: "center", padding: spacing.lg, gap: spacing.md },
  gateTitle: { ...type.title, color: colors.white },
  gateBody: { ...type.body, color: colors.textFaint },
});
