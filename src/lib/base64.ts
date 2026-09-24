/**
 * Base64 to bytes, for Storage uploads.
 *
 * Both the camera and the image picker can hand back base64 directly, which is
 * why nothing here reads the filesystem: supabase-js wants an ArrayBuffer-ish
 * body, and going via base64 avoids pulling in expo-file-system just to read a
 * file the SDK already gave us.
 */
export function toBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
