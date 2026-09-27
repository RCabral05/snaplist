import { Image } from "expo-image";
import { StyleSheet, Text, View } from "react-native";

import { colors, fonts } from "@/theme";

/** Up to two letters, from a name if there is one and the handle if not. */
function initials(name?: string | null, fallback?: string | null): string {
  const source = (name ?? "").trim() || (fallback ?? "").trim();
  if (!source) return "?";
  const words = source.split(/\s+/).filter(Boolean);
  const letters = words.length > 1 ? words[0][0] + words[1][0] : source.slice(0, 2);
  return letters.toUpperCase();
}

/**
 * The one bright thing on the screen, so it carries a hairline ring to sit it
 * on the dark rather than float. Initials when there is no photo - a silhouette
 * icon looks like a failed load, letters look chosen.
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
  const box = {
    width: size,
    height: size,
    borderRadius: size / 2,
    borderWidth: size >= 64 ? 1 : StyleSheet.hairlineWidth,
  };

  if (url) {
    return (
      <Image
        source={{ uri: url }}
        style={[s.image, box]}
        contentFit="cover"
        transition={140}
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
  image: { backgroundColor: colors.raisedHigh, borderColor: colors.lineStrong },
  fallback: {
    backgroundColor: colors.raisedHigh,
    borderColor: colors.lineStrong,
    alignItems: "center",
    justifyContent: "center",
  },
  initials: { fontFamily: fonts.sansSemi, color: colors.inkDim, letterSpacing: 0.5 },
});
