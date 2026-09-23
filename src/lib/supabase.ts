import AsyncStorage from "@react-native-async-storage/async-storage";
import { createClient } from "@supabase/supabase-js";
import { AppState } from "react-native";

// Snaplist's own Supabase project - deliberately not the weekly-rivals one, so a
// schema change to either product cannot break the other. The anon key ships in
// the binary and that is fine: row-level security is what protects the data.
const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    "Supabase config missing. Copy .env.example to .env.local, fill in EXPO_PUBLIC_SUPABASE_*, then restart `expo start`.",
  );
}

export const supabase = createClient(url, anonKey, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false, // no OAuth redirects on native; we use id tokens
  },
});

// Only refresh tokens while the app is in the foreground.
AppState.addEventListener("change", (state) => {
  if (state === "active") supabase.auth.startAutoRefresh();
  else supabase.auth.stopAutoRefresh();
});
