import * as ImagePicker from "expo-image-picker";

import { toBytes } from "./base64";
import { supabase } from "./supabase";

const BUCKET = "avatars";

export type PickedImage = { base64: string; mime: string; ext: string };

/**
 * Opens the library and returns the chosen image, or null if the seller backed
 * out. Cropping is forced square because every place an avatar appears is a
 * circle, and letting the OS crop is kinder than doing it for them afterwards.
 */
export async function pickAvatar(): Promise<PickedImage | null> {
  const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error("Snaplist needs access to your photos to set a picture.");
  }

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ["images"],
    allowsEditing: true,
    aspect: [1, 1],
    // An avatar is never drawn above ~96pt. Quality is the only lever here
    // without pulling in expo-image-manipulator; worth revisiting if uploads
    // from newer phones turn out slow.
    quality: 0.7,
    base64: true,
  });
  if (result.canceled) return null;

  const asset = result.assets[0];
  if (!asset?.base64) throw new Error("Could not read that image.");

  const mime = asset.mimeType ?? "image/jpeg";
  return { base64: asset.base64, mime, ext: mime === "image/png" ? "png" : "jpg" };
}

/** Uploads to <uid>/... - the one prefix the storage policy lets them write. */
export async function uploadAvatar(uid: string, picked: PickedImage): Promise<string> {
  const name = `avatar-${Date.now()}.${picked.ext}`;
  const path = `${uid}/${name}`;

  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, toBytes(picked.base64), { contentType: picked.mime, upsert: true });
  if (error) throw error;

  // A fixed filename would be served stale: the bucket is public, so its URL
  // sits in a CDN and in the phone's image cache, and the seller would change
  // their picture and watch the old one stay. A fresh name each time is the
  // cheapest cache bust; the previous objects get swept here so the folder does
  // not grow one file per edit forever.
  await sweep(uid, name);

  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
}

/** Drops every object the seller has in the bucket. Used by "Remove photo". */
export async function clearAvatar(uid: string): Promise<void> {
  await sweep(uid, null);
}

async function sweep(uid: string, keep: string | null): Promise<void> {
  const { data } = await supabase.storage.from(BUCKET).list(uid);
  const stale = (data ?? []).filter((f) => f.name !== keep).map((f) => `${uid}/${f.name}`);
  // A failed sweep leaves an orphan file, which is untidy but harmless - never
  // worth failing the seller's edit over.
  if (stale.length) await supabase.storage.from(BUCKET).remove(stale);
}
