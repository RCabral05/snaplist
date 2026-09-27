import type { Session, User } from "@supabase/supabase-js";
import * as AppleAuthentication from "expo-apple-authentication";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from "react";

import { supabase } from "./supabase";

const googleWebClientId = process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID;
const googleIosClientId = process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID;

/**
 * Google sign-in is optional twice over, and both have to be true before the
 * button can appear:
 *
 *   1. the OAuth client IDs exist (someone made them in the Google console), and
 *   2. the native module is actually in this binary.
 *
 * The second one is easy to forget. Adding the package changes the native build,
 * so any dev client made before that has no RNGoogleSignin - and importing it at
 * the top of this file took the whole app down on launch, for a feature that was
 * switched off anyway. It is loaded defensively instead: one attempt, cached, and
 * a miss just means no Google button.
 */
type GoogleSdk = typeof import("@react-native-google-signin/google-signin");

let sdk: GoogleSdk | null | undefined;
function google(): GoogleSdk | null {
  if (sdk !== undefined) return sdk;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const loaded = require("@react-native-google-signin/google-signin") as GoogleSdk;
    loaded.GoogleSignin.configure({
      // The Web client ID is the audience of the idToken Supabase validates.
      webClientId: googleWebClientId,
      iosClientId: googleIosClientId,
    });
    sdk = loaded;
  } catch {
    sdk = null; // not built into this binary
  }
  return sdk;
}

export const googleConfigured = !!googleWebClientId && !!googleIosClientId && !!google();

/** Mirrors public.profiles - one row per auth user, created by a trigger. */
export type Profile = {
  id: string;
  display_name: string;
  /** Null until they pick one. Unique case-insensitively; see migration 0013. */
  username: string | null;
  /** Public Storage URL, or null while they are still the initials. */
  avatar_url: string | null;
  created_at: string;
};

/** The fields someone may change about themselves. */
export type ProfilePatch = Partial<Pick<Profile, "display_name" | "avatar_url">>;

type AuthContextValue = {
  session: Session | null;
  user: User | null;
  profile: Profile | null;
  /** True until the persisted session has been restored and the profile loaded. */
  isLoading: boolean;
  signInWithApple: () => Promise<void>;
  signInWithGoogle: () => Promise<void>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
  /** Writes the patch and refreshes, so every screen sees the new value at once. */
  updateProfile: (patch: ProfilePatch) => Promise<void>;
  /** Resolves once the name is theirs; throws "username_taken" if it is not. */
  claimUsername: (username: string) => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<Session | null>(null);
  const [sessionLoading, setSessionLoading] = useState(true);
  // Profile tagged with the uid it belongs to, so a stale row from a previous
  // account is never shown for the next one.
  const [snapshot, setSnapshot] = useState<{ uid: string; profile: Profile | null } | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setSessionLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  const user = session?.user ?? null;
  const uid = user?.id;

  const loadProfile = useCallback((forUid: string) => {
    return supabase
      .from("profiles")
      .select("id, display_name, username, avatar_url, created_at")
      .eq("id", forUid)
      .maybeSingle()
      .then(({ data, error }) => {
        if (error) console.error("profile load failed", error);
        setSnapshot({ uid: forUid, profile: (data as Profile | null) ?? null });
      });
  }, []);

  useEffect(() => {
    if (!uid) return;
    void loadProfile(uid);
  }, [uid, loadProfile]);

  const profile = uid && snapshot?.uid === uid ? snapshot.profile : null;
  const profileLoading = !!uid && snapshot?.uid !== uid;
  const isLoading = sessionLoading || profileLoading;

  const signInWithApple = useCallback(async () => {
    let credential: AppleAuthentication.AppleAuthenticationCredential;
    try {
      credential = await AppleAuthentication.signInAsync({
        requestedScopes: [
          AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
          AppleAuthentication.AppleAuthenticationScope.EMAIL,
        ],
      });
    } catch (e: any) {
      if (e?.code === "ERR_REQUEST_CANCELED") return; // user dismissed the sheet
      throw e;
    }
    if (!credential.identityToken) throw new Error("Apple did not return an identity token.");

    const { data, error } = await supabase.auth.signInWithIdToken({
      provider: "apple",
      token: credential.identityToken,
    });
    if (error) throw error;

    // Apple sends the name only on the very first authorization, and it is not in
    // the id token, so the profiles trigger cannot see it. Set it here instead.
    const { givenName, familyName } = credential.fullName ?? {};
    const name = [givenName, familyName].filter(Boolean).join(" ");
    if (name && data.user) {
      await supabase.from("profiles").update({ display_name: name }).eq("id", data.user.id);
    }
  }, []);

  const signInWithGoogle = useCallback(async () => {
    const g = google();
    if (!g) throw new Error("Google sign-in is not available in this build.");
    await g.GoogleSignin.hasPlayServices(); // no-op on iOS
    const response = await g.GoogleSignin.signIn();
    if (g.isCancelledResponse(response)) return;
    if (!g.isSuccessResponse(response) || !response.data.idToken) {
      throw new Error("Google sign-in did not return an ID token.");
    }
    const { error } = await supabase.auth.signInWithIdToken({
      provider: "google",
      token: response.data.idToken,
    });
    if (error) throw error;
  }, []);

  const signOut = useCallback(async () => {
    // Also clear Google's cached account so the chooser shows next time.
    await google()?.GoogleSignin.signOut().catch(() => {});
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  }, []);

  const refreshProfile = useCallback(async () => {
    if (uid) await loadProfile(uid);
  }, [uid, loadProfile]);

  const updateProfile = useCallback(
    async (patch: ProfilePatch) => {
      if (!uid) throw new Error("Not signed in.");
      const { error } = await supabase.from("profiles").update(patch).eq("id", uid);
      if (error) throw error;
      await loadProfile(uid);
    },
    [uid, loadProfile],
  );

  const claimUsername = useCallback(
    async (username: string) => {
      const { error } = await supabase.rpc("claim_username", { candidate: username });
      // Postgres raises bare codes ("username_taken"); surface them unchanged so
      // the screen can decide what to say.
      if (error) throw new Error(error.message);
      if (uid) await loadProfile(uid);
    },
    [uid, loadProfile],
  );

  const value = useMemo(
    () => ({
      session,
      user,
      profile,
      isLoading,
      signInWithApple,
      signInWithGoogle,
      signOut,
      refreshProfile,
      updateProfile,
      claimUsername,
    }),
    [
      session,
      user,
      profile,
      isLoading,
      signInWithApple,
      signInWithGoogle,
      signOut,
      refreshProfile,
      updateProfile,
      claimUsername,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}
