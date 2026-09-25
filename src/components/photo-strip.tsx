import { Image } from "expo-image";
import { ScrollView, StyleSheet, Text, View, Pressable, ActivityIndicator } from "react-native";

import { usePhotoUrl } from "@/lib/photos";
import { colors, radius, spacing, type } from "@/theme";

import { Icon } from "./icon";

/**
 * Every photo on a listing, in order, with the first marked as the cover.
 *
 * Order is the feature, not decoration: photos[0] is what the grid, the featured
 * rail and every search result show, so "make cover" is the single most useful
 * thing a seller can do here and it needs to be one tap from the thumbnail.
 */
export function PhotoStrip({
  photos,
  busy,
  canAdd,
  onAdd,
  onSelect,
}: {
  photos: string[];
  busy?: boolean;
  canAdd: boolean;
  onAdd: () => void;
  onSelect: (index: number) => void;
}) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.strip}>
      {photos.map((photo, i) => (
        <Thumb key={photo} photo={photo} cover={i === 0} onPress={() => onSelect(i)} />
      ))}

      {canAdd ? (
        <Pressable
          onPress={onAdd}
          disabled={busy}
          style={({ pressed }) => [s.add, pressed && s.pressed]}
        >
          {busy ? (
            <ActivityIndicator size="small" color={colors.inkFaint} />
          ) : (
            <>
              <Icon name="plus" size={18} color={colors.inkDim} weight="medium" />
              <Text style={s.addText}>Add</Text>
            </>
          )}
        </Pressable>
      ) : null}
    </ScrollView>
  );
}

function Thumb({
  photo,
  cover,
  onPress,
}: {
  photo: string;
  cover: boolean;
  onPress: () => void;
}) {
  const url = usePhotoUrl(photo);
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [s.thumb, pressed && s.pressed]}>
      {url ? (
        <Image source={{ uri: url }} style={s.thumbPhoto} contentFit="cover" transition={120} />
      ) : (
        <View style={s.thumbEmpty} />
      )}
      {cover ? (
        <View style={s.cover}>
          <Text style={s.coverText}>Cover</Text>
        </View>
      ) : null}
    </Pressable>
  );
}

const W = 78;
const H = 98;

const s = StyleSheet.create({
  strip: { gap: spacing.sm, paddingVertical: spacing.xs },
  pressed: { opacity: 0.7 },
  thumb: {
    width: W,
    height: H,
    borderRadius: radius.sm,
    overflow: "hidden",
    backgroundColor: colors.paperAlt,
    justifyContent: "flex-end",
  },
  thumbPhoto: { position: "absolute", top: 0, left: 0, right: 0, bottom: 0 },
  thumbEmpty: { flex: 1, backgroundColor: colors.sand },
  cover: { backgroundColor: "rgba(10,9,7,0.72)", paddingVertical: 3, alignItems: "center" },
  coverText: { ...type.label, fontSize: 8, color: colors.white },
  add: {
    width: W,
    height: H,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.ruleStrong,
    borderStyle: "dashed",
    alignItems: "center",
    justifyContent: "center",
    gap: 3,
  },
  addText: { ...type.label, fontSize: 8, color: colors.inkDim },
});
