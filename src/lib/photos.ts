import * as Crypto from "expo-crypto";
import { useEffect, useState } from "react";

import { toBytes } from "./base64";
import { supabase } from "./supabase";

const BUCKET = "listing-photos";
/** An hour is the default; we re-sign a minute early to avoid a race at the edge. */
const TTL_SECONDS = 3600;

/**
 * A draft photo is one of two things, and the string itself says which:
 *
 *   file://...   a capture that has not finished uploading yet
 *   <uid>/...    a Storage object path, the durable form stored on the row
 *
 * Keeping both in one field means the rest of the app carries on treating
 * `photos` as a list of photos, and only the component that draws one has to
 * care which kind it is holding.
 */
export const isStoragePath = (photo: string) =>
  !photo.startsWith("file://") && !photo.startsWith("http");

export async function uploadListingPhoto(
  uid: string,
  listingId: string,
  base64: string,
  mime = "image/jpeg",
): Promise<string> {
  const ext = mime === "image/png" ? "png" : "jpg";
  const path = `${uid}/${listingId}/${Crypto.randomUUID()}.${ext}`;

  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, toBytes(base64), { contentType: mime, upsert: false });
  if (error) throw error;

  return path;
}

/** Everything under this listing's folder. Called when a draft is deleted. */
export async function removeListingPhotos(uid: string, listingId: string): Promise<void> {
  const prefix = `${uid}/${listingId}`;
  const { data } = await supabase.storage.from(BUCKET).list(prefix);
  const paths = (data ?? []).map((f) => `${prefix}/${f.name}`);
  if (paths.length) await supabase.storage.from(BUCKET).remove(paths);
}

const cache = new Map<string, { url: string; expiresAt: number }>();

export async function signPhoto(path: string): Promise<string | null> {
  const hit = cache.get(path);
  if (hit && hit.expiresAt > Date.now()) return hit.url;

  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, TTL_SECONDS);
  if (error || !data?.signedUrl) return null;

  cache.set(path, { url: data.signedUrl, expiresAt: Date.now() + (TTL_SECONDS - 60) * 1000 });
  return data.signedUrl;
}

/**
 * A URI the <Image> can actually load. Local captures pass straight through, so
 * a photo just taken renders immediately rather than waiting on its own upload.
 */
export function usePhotoUrl(photo?: string): string | null {
  const local = photo && !isStoragePath(photo) ? photo : null;
  const needsSigning = !!photo && !local;
  const [signed, setSigned] = useState<{ for: string; url: string | null } | null>(null);

  useEffect(() => {
    if (!needsSigning || !photo) return;
    let alive = true;
    signPhoto(photo).then((url) => {
      if (alive) setSigned({ for: photo, url });
    });
    return () => {
      alive = false;
    };
  }, [photo, needsSigning]);

  if (local) return local;
  // Not `signed?.for === photo`: with no photo at all both sides are undefined
  // and the comparison passes while `signed` is still null.
  if (signed && signed.for === photo) return signed.url;
  return null;
}
