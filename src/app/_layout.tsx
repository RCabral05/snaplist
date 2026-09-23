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
import { colors } from "@/theme";

function RootNavigator() {
  const { user, isLoading } = useAuth();

  // Hold the navigator until the persisted session is restored, otherwise the
  // sign-in screen flashes for a fraction of a second on every cold start.
  if (isLoading) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
        <ActivityIndicator color={colors.ember} />
      </View>
    );
  }

  return (
    <Stack
      screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.paper } }}
    >
      <Stack.Protected guard={!!user}>
        <Stack.Screen name="(app)" />
        <Stack.Screen name="draft/[id]" />
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
        <RootNavigator />
      </AuthProvider>
      <StatusBar style="dark" />
    </GestureHandlerRootView>
  );
}
