import { Image } from "expo-image";
import { StyleSheet, Text, View } from "react-native";

import { colors, fonts } from "@/theme";

/** Up to two letters, from a display name if there is one and the handle if not. */
function initials(name?: string | null, fallback?: string | null): string {
  const source = (name ?? "").trim() || (fallback ?? "").trim();
  if (!source) return "?";
  const words = source.split(/\s+/).filter(Boolean);
  const letters = words.length > 1 ? words[0][0] + words[1][0] : source.slice(0, 2);
  return letters.toUpperCase();
}

/**
 * The seller, as a circle. Falls back to initials rather than a generic silhouette:
 * a grey person icon looks like a loading failure, initials look deliberate.
 */
export function Avatar({
  url,
  name,
  handle,
  size = 48,
}: {
  url?: string | null;
  name?: string | null;
  handle?: string | null;
  size?: number;
}) {
  const box = { width: size, height: size, borderRadius: size / 2 };

  if (url) {
    return (
      <Image
        source={{ uri: url }}
        style={[s.image, box]}
        contentFit="cover"
        transition={120}
        // The URL changes filename on every upload, so nothing is ever served
        // stale and the disk cache is safe to use.
        cachePolicy="disk"
      />
    );
  }

  return (
    <View style={[s.fallback, box]}>
      <Text style={[s.initials, { fontSize: size * 0.36 }]}>{initials(name, handle)}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  image: { backgroundColor: colors.sand },
  fallback: { backgroundColor: colors.sand, alignItems: "center", justifyContent: "center" },
  initials: { fontFamily: fonts.sansBold, color: colors.inkDim, letterSpacing: 0.5 },
});
