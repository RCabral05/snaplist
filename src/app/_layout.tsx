import {
  Archivo_400Regular,
  Archivo_500Medium,
  Archivo_600SemiBold,
  Archivo_700Bold,
} from "@expo-google-fonts/archivo";
import { useFonts } from "expo-font";
import { DarkTheme, Stack, ThemeProvider } from "expo-router";
import { StatusBar } from "expo-status-bar";
import * as SystemUI from "expo-system-ui";
import { ActivityIndicator, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";

import { AuthProvider, useAuth } from "@/lib/auth";
import { MenuProvider } from "@/lib/menu";
import { colors } from "@/theme";

// The native root view sits *behind* every screen, and it is white by default.
// A push or a modal animates the new screen in over that root, so for the two
// or three frames where neither screen covers it you get a white flash. Styling
// the React tree cannot reach it - `contentStyle` colours the screen, not the
// window underneath. This is the one thing that does, and it has to run before
// the first frame, so it is module scope rather than an effect.
SystemUI.setBackgroundColorAsync(colors.void).catch(() => {});

// expo-router mounts its NavigationContainer with `theme = DefaultTheme`, whose
// background is rgb(242, 242, 242). That colour is what a stack transition is
// drawn against, and `contentStyle` cannot reach it - it paints the screen, not
// the container the screen slides across. Hence a near-white flash on every
// push, no matter how dark the screens themselves are.
const navTheme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    background: colors.void,
    card: colors.raised,
    border: colors.line,
    text: colors.ink,
    primary: colors.ember,
  },
};

const screenOptions = {
  headerShown: false,
  contentStyle: { backgroundColor: colors.void },
} as const;

function RootNavigator() {
  const { user, isLoading } = useAuth();

  // Two states: signed out, and in. Signing in lands straight on home.
  if (isLoading) {
    return (
      <View
        style={{
          flex: 1,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: colors.void,
        }}
      >
        <ActivityIndicator color={colors.ember} />
      </View>
    );
  }

  return (
    <ThemeProvider value={navTheme}>
      <Stack screenOptions={screenOptions}>
        <Stack.Protected guard={!!user}>
          <Stack.Screen name="(app)" />
          <Stack.Screen name="edit-profile" options={{ presentation: "modal" }} />
        </Stack.Protected>
        <Stack.Protected guard={!user}>
          <Stack.Screen name="(auth)" />
        </Stack.Protected>
      </Stack>
    </ThemeProvider>
  );
}

export default function RootLayout() {
  const [fontsReady] = useFonts({
    Archivo_400Regular,
    Archivo_500Medium,
    Archivo_600SemiBold,
    Archivo_700Bold,
  });

  // Not `null`: returning nothing here uncovers the root view for however long
  // the fonts take, which is the same white flash at launch.
  if (!fontsReady) return <View style={{ flex: 1, backgroundColor: colors.void }} />;

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.void }}>
      <AuthProvider>
        <MenuProvider>
          <RootNavigator />
        </MenuProvider>
      </AuthProvider>
      <StatusBar style="light" />
    </GestureHandlerRootView>
  );
}
