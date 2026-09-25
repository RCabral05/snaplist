import AsyncStorage from "@react-native-async-storage/async-storage";
import * as Crypto from "expo-crypto";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from "react";

import { useAuth } from "./auth";
import { toBytes } from "./base64";
import type { PickedImage } from "./avatar";
import { supabase } from "./supabase";

const LOGO_BUCKET = "brand-logos";
const ACTIVE_KEY = "snaplist.active-brand.v1";

/** A brand as its owner sees it. Buyers get public_brands, which drops owner_id. */
export type Brand = {
  id: string;
  owner_id: string;
  slug: string;
  name: string;
  logo_url: string | null;
  bio: string | null;
  created_at: string;
  updated_at: string;
};

export type BrandPatch = Partial<Pick<Brand, "name" | "logo_url" | "bio">>;

const COLUMNS = "id, owner_id, slug, name, logo_url, bio, created_at, updated_at";

export async function fetchMyBrands(): Promise<Brand[]> {
  const { data, error } = await supabase
    .from("brands")
    .select(COLUMNS)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []) as Brand[];
}

/**
 * Slug and row in one statement. Checking then inserting from here would race:
 * two people can both be told a slug is free before either writes.
 */
export async function createBrand(slug: string, name: string): Promise<Brand> {
  const { data, error } = await supabase.rpc("create_brand", {
    candidate: slug.trim(),
    brand_name: name.trim(),
  });
  if (error) throw new Error(error.message);
  return data as Brand;
}

export async function renameBrand(id: string, slug: string): Promise<Brand> {
  const { data, error } = await supabase.rpc("rename_brand", {
    target: id,
    candidate: slug.trim(),
  });
  if (error) throw new Error(error.message);
  return data as Brand;
}

export async function updateBrand(id: string, patch: BrandPatch): Promise<void> {
  const { error } = await supabase
    .from("brands")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

/**
 * Logos go in a public bucket - a storefront logo is meant to be seen by buyers
 * who are not signed in - with writes confined to <uid>/ like every other bucket
 * here. The filename changes on every upload so nothing is served stale.
 */
export async function uploadBrandLogo(
  uid: string,
  brandId: string,
  picked: PickedImage,
): Promise<string> {
  const path = `${uid}/${brandId}/${Crypto.randomUUID()}.${picked.ext}`;
  const { error } = await supabase.storage
    .from(LOGO_BUCKET)
    .upload(path, toBytes(picked.base64), { contentType: picked.mime, upsert: false });
  if (error) throw error;

  const { data } = await supabase.storage.from(LOGO_BUCKET).list(`${uid}/${brandId}`);
  const stale = (data ?? [])
    .filter((f) => !path.endsWith(f.name))
    .map((f) => `${uid}/${brandId}/${f.name}`);
  if (stale.length) await supabase.storage.from(LOGO_BUCKET).remove(stale);

  return supabase.storage.from(LOGO_BUCKET).getPublicUrl(path).data.publicUrl;
}

type BrandContextValue = {
  brands: Brand[];
  /** The brand new listings belong to, and the one the seller tabs are showing. */
  active: Brand | null;
  isLoading: boolean;
  setActive: (id: string) => void;
  refresh: () => Promise<void>;
};

const BrandContext = createContext<BrandContextValue | null>(null);

export function BrandProvider({ children }: PropsWithChildren) {
  const { user } = useAuth();
  const uid = user?.id;

  const [brands, setBrands] = useState<Brand[] | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);

  // Fetching and applying are kept apart so nothing sets state synchronously
  // inside the effect below - including the signed-out case, which would
  // otherwise return early having already called setBrands.
  const fetchState = useCallback(async () => {
    if (!uid) return { rows: [] as Brand[], stored: null as string | null };
    const [rows, stored] = await Promise.all([
      fetchMyBrands(),
      AsyncStorage.getItem(ACTIVE_KEY).catch(() => null),
    ]);
    return { rows, stored };
  }, [uid]);

  const apply = useCallback((rows: Brand[], stored: string | null) => {
    setBrands(rows);
    // Fall back to the first brand rather than none: every seller screen assumes
    // an active brand once past onboarding, and a stored id can outlive a brand
    // that has since been deleted or signed out of.
    setActiveId((current) => {
      const candidate = current ?? stored;
      return rows.some((b) => b.id === candidate) ? candidate : (rows[0]?.id ?? null);
    });
  }, []);

  useEffect(() => {
    let alive = true;
    fetchState()
      .then(({ rows, stored }) => {
        if (alive) apply(rows, stored);
      })
      .catch(() => {
        if (alive) setBrands([]);
      });
    return () => {
      alive = false;
    };
  }, [fetchState, apply]);

  const load = useCallback(async () => {
    const { rows, stored } = await fetchState();
    apply(rows, stored);
  }, [fetchState, apply]);

  const setActive = useCallback((id: string) => {
    setActiveId(id);
    AsyncStorage.setItem(ACTIVE_KEY, id).catch(() => {});
  }, []);

  const value = useMemo<BrandContextValue>(() => {
    const list = brands ?? [];
    return {
      brands: list,
      active: list.find((b) => b.id === activeId) ?? null,
      isLoading: brands === null,
      setActive,
      refresh: load,
    };
  }, [brands, activeId, setActive, load]);

  return <BrandContext.Provider value={value}>{children}</BrandContext.Provider>;
}

export function useBrands() {
  const ctx = useContext(BrandContext);
  if (!ctx) throw new Error("useBrands must be used inside <BrandProvider>");
  return ctx;
}
