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

/** Mirrors public.profiles - one row per auth user, created by a trigger. */
export type Profile = {
  id: string;
  display_name: string;
};

type AuthContextValue = {
  session: Session | null;
  user: User | null;
  profile: Profile | null;
  /** True until the persisted session has been restored and the profile loaded. */
  isLoading: boolean;
  signInWithApple: () => Promise<void>;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signUpWithEmail: (email: string, password: string) => Promise<{ needsConfirmation: boolean }>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
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
      .select("id, display_name")
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

  const signInWithEmail = useCallback(async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw error;
  }, []);

  const signUpWithEmail = useCallback(async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signUp({ email: email.trim(), password });
    if (error) throw error;
    // With email confirmation on, signUp returns a user but no session.
    return { needsConfirmation: !data.session };
  }, []);

  const signOut = useCallback(async () => {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  }, []);

  const refreshProfile = useCallback(async () => {
    if (uid) await loadProfile(uid);
  }, [uid, loadProfile]);

  const value = useMemo(
    () => ({
      session,
      user,
      profile,
      isLoading,
      signInWithApple,
      signInWithEmail,
      signUpWithEmail,
      signOut,
      refreshProfile,
    }),
    [
      session,
      user,
      profile,
      isLoading,
      signInWithApple,
      signInWithEmail,
      signUpWithEmail,
      signOut,
      refreshProfile,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}
