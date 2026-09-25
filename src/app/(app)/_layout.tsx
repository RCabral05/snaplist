import type { SFSymbol } from "expo-symbols";
import { Tabs } from "expo-router";
import { StyleSheet, View, type ColorValue } from "react-native";

import { Icon } from "@/components/icon";
import { colors, radius, shadow } from "@/theme";

/**
 * The sell tab is the product, so it is drawn as an action rather than a
 * destination: a filled ember disc, coloured whether or not it is the current
 * tab. The theme keeps every other piece of chrome grey precisely so this one
 * thing can be the only saturated colour on screen.
 */
function SellTab() {
  return (
    <View style={s.sell}>
      <Icon name="plus" size={20} color={colors.white} weight="semibold" />
    </View>
  );
}

function tabIcon(on: SFSymbol, off: SFSymbol) {
  return function TabIcon({ focused, color }: { focused: boolean; color: ColorValue }) {
    return <Icon name={focused ? on : off} size={23} color={color} />;
  };
}

export default function AppLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.ink,
        tabBarInactiveTintColor: colors.inkFaint,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.rule,
          borderTopWidth: StyleSheet.hairlineWidth,
          height: 84,
        },
        // Sentence case at 11pt, not the uppercase label style: four wide
        // letter-spaced words across a phone leaves no air between them.
        // No labels. Four glyphs and one coloured disc is legible on its own, and
        // dropping the words gives the bar the quiet the rest of the chrome has.
        tabBarShowLabel: false,
        tabBarItemStyle: { paddingTop: 10 },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{ title: "Shop", tabBarIcon: tabIcon("bag.fill", "bag") }}
      />
      <Tabs.Screen
        name="sell"
        options={{ title: "Sell", tabBarIcon: SellTab, tabBarLabel: () => null }}
      />
      <Tabs.Screen
        name="listings"
        options={{ title: "Brand", tabBarIcon: tabIcon("storefront.fill", "storefront") }}
      />
      <Tabs.Screen
        name="account"
        options={{
          title: "Account",
          tabBarIcon: tabIcon("person.crop.circle.fill", "person.crop.circle"),
        }}
      />
    </Tabs>
  );
}

const s = StyleSheet.create({
  sell: {
    width: 46,
    height: 46,
    borderRadius: radius.pill,
    backgroundColor: colors.ember,
    alignItems: "center",
    justifyContent: "center",
    marginTop: -2,
    ...shadow.lift,
  },
});
