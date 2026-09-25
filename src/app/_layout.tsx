import {
  Archivo_400Regular,
  Archivo_500Medium,
  Archivo_600SemiBold,
  Archivo_700Bold,
} from "@expo-google-fonts/archivo";
import { useFonts } from "expo-font";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { ActivityIndicator, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";

import { AuthProvider, useAuth } from "@/lib/auth";
import { BrandProvider, useBrands } from "@/lib/brands";
import { colors } from "@/theme";

function RootNavigator() {
  const { user, isLoading: authLoading } = useAuth();
  const { brands, isLoading: brandsLoading } = useBrands();

  // Signed in with no brand is its own state, the way "signed in without a
  // username" used to be. Gating here rather than redirecting from inside a
  // screen means everything under (app) can assume an active brand exists.
  const needsBrand = !!user && brands.length === 0;

  // Hold the navigator until the session is restored and, if there is one, its
  // brands have loaded. Otherwise onboarding flashes on every cold start.
  if (authLoading || (!!user && brandsLoading)) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
        <ActivityIndicator color={colors.ember} />
      </View>
    );
  }

  return (
    <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.paper } }}>
      <Stack.Protected guard={!!user && !needsBrand}>
        <Stack.Screen name="(app)" />
        <Stack.Screen name="draft/[id]" />
        <Stack.Screen name="edit-profile" options={{ presentation: "modal" }} />
        <Stack.Screen name="brand-settings" options={{ presentation: "modal" }} />
        <Stack.Screen name="brand/[slug]" />
        <Stack.Screen name="item/[id]" />
      </Stack.Protected>
      {/* Reachable in both signed-in states: it is onboarding when there is no
          brand yet, and a push from Account when adding another. */}
      <Stack.Protected guard={!!user}>
        <Stack.Screen name="new-brand" />
      </Stack.Protected>
      <Stack.Protected guard={!user}>
        <Stack.Screen name="(auth)" />
      </Stack.Protected>
    </Stack>
  );
}

export default function RootLayout() {
  const [fontsReady] = useFonts({
    Archivo_400Regular,
    Archivo_500Medium,
    Archivo_600SemiBold,
    Archivo_700Bold,
  });

  if (!fontsReady) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.paper }}>
      <AuthProvider>
        <BrandProvider>
          <RootNavigator />
        </BrandProvider>
      </AuthProvider>
      <StatusBar style="dark" />
    </GestureHandlerRootView>
  );
}
