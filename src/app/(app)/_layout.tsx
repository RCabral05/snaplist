import { Tabs } from "expo-router";
import { StyleSheet, Text, View } from "react-native";

import { colors, type } from "@/theme";

/** The sell tab is the product; it gets the only colour in the bar. */
function SellTab({ focused }: { focused: boolean }) {
  return (
    <View style={[s.sell, focused && s.sellOn]}>
      <Text style={s.sellMark}>+</Text>
    </View>
  );
}

export default function AppLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.ink,
        tabBarInactiveTintColor: colors.inkFaint,
        tabBarStyle: { backgroundColor: colors.paper, borderTopColor: colors.border },
        tabBarLabelStyle: { ...type.label, fontSize: 10 },
      }}
    >
      <Tabs.Screen name="index" options={{ title: "Shop" }} />
      <Tabs.Screen
        name="sell"
        options={{ title: "Sell", tabBarIcon: ({ focused }) => <SellTab focused={focused} /> }}
      />
      <Tabs.Screen name="listings" options={{ title: "Listings" }} />
      <Tabs.Screen name="account" options={{ title: "Account" }} />
    </Tabs>
  );
}

const s = StyleSheet.create({
  sell: {
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: colors.ruleStrong,
    alignItems: "center",
    justifyContent: "center",
  },
  sellOn: { backgroundColor: colors.ember },
  sellMark: { color: colors.white, fontSize: 20, lineHeight: 24, fontFamily: "Archivo_700Bold" },
});
