import { usePathname, useRouter, type Href } from "expo-router";
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import {
  Animated,
  Easing,
  Pressable,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { SFSymbol } from "expo-symbols";

import { Avatar } from "@/components/avatar";
import { Icon } from "@/components/icon";
import { useAuth } from "@/lib/auth";
import { colors, radius, spacing, type } from "@/theme";

/**
 * The menu, mounted once above the navigator instead of inside a screen.
 *
 * The first version of this was a `Modal`. On iOS that is a genuine native
 * presentation, so tapping a destination meant dismissing a view controller and
 * pushing a route in the same breath - and between the two there is a frame
 * where neither covers the window, which is the white flash. Nothing about the
 * colours fixed it because it was never a colour problem.
 *
 * Here the panel is an absolutely positioned sibling of the navigator inside
 * the same React tree. It draws over whatever is on screen, navigation happens
 * underneath it with nothing to dismiss, and the push is already done by the
 * time the panel has finished sliding out.
 */
const MenuContext = createContext<{ open: () => void }>({ open: () => {} });

export const useMenu = () => useContext(MenuContext);

export function MenuProvider({ children }: { children: ReactNode }) {
  // `shown` keeps the panel in the tree for the length of the close, so it
  // slides out rather than disappearing.
  const [shown, setShown] = useState(false);
  const [slide] = useState(() => new Animated.Value(0));

  const open = useCallback(() => setShown(true), []);

  return (
    <MenuContext.Provider value={{ open }}>
      <View style={s.root}>
        {children}
        {shown ? <Panel slide={slide} dismiss={() => setShown(false)} /> : null}
      </View>
    </MenuContext.Provider>
  );
}

function Panel({ slide, dismiss }: { slide: Animated.Value; dismiss: () => void }) {
  const router = useRouter();
  const pathname = usePathname();
  const { user, profile, signOut } = useAuth();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();

  const panelWidth = Math.min(330, width * 0.84);

  useEffect(() => {
    Animated.timing(slide, {
      toValue: 1,
      duration: 240,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    }).start();
  }, [slide]);

  const close = useCallback(
    (then?: () => void) => {
      // The navigation runs first, on purpose. It happens beneath the panel, so
      // it is invisible, and by the time the panel is gone the new screen is
      // already there - no gap, and nothing to animate into.
      then?.();
      Animated.timing(slide, {
        toValue: 0,
        duration: 190,
        easing: Easing.in(Easing.cubic),
        useNativeDriver: true,
      }).start(({ finished }) => {
        if (finished) dismiss();
      });
    },
    [slide, dismiss],
  );

  const go = (href: Href) => close(pathname === href ? undefined : () => router.navigate(href));

  const name = profile?.display_name?.trim();

  return (
    <View style={s.stage} pointerEvents="box-none">
      <Animated.View style={[s.scrim, { opacity: slide }]}>
        <Pressable style={s.fill} onPress={() => close()} accessibilityLabel="Close menu" />
      </Animated.View>

      <Animated.View
        style={[
          s.panel,
          {
            width: panelWidth,
            paddingTop: insets.top + spacing.lg,
            paddingBottom: insets.bottom + spacing.lg,
            transform: [
              {
                translateX: slide.interpolate({
                  inputRange: [0, 1],
                  outputRange: [-panelWidth, 0],
                }),
              },
            ],
          },
        ]}
      >
        <Pressable style={s.who} onPress={() => go("/profile")}>
          <Avatar url={profile?.avatar_url} name={name} handle={profile?.username} size={52} />
          <View style={s.whoText}>
            <Text style={s.whoName} numberOfLines={1}>
              {name || "Your profile"}
            </Text>
            <Text style={s.whoSub} numberOfLines={1}>
              {profile?.username ? `@${profile.username}` : (user?.email ?? "")}
            </Text>
          </View>
        </Pressable>

        <View style={s.rule} />

        <View style={s.items}>
          <Item icon="house" label="Home" active={pathname === "/"} onPress={() => go("/")} />
          <Item
            icon="person"
            label="Profile"
            active={pathname === "/profile"}
            onPress={() => go("/profile")}
          />
          <Item icon="square.and.pencil" label="Edit profile" onPress={() => go("/edit-profile")} />
        </View>

        <View style={s.spacer} />

        <Pressable style={s.signOut} onPress={() => close(() => void signOut().catch(() => {}))}>
          <Icon name="rectangle.portrait.and.arrow.right" size={17} color={colors.inkFaint} />
          <Text style={s.signOutText}>Sign out</Text>
        </Pressable>
      </Animated.View>
    </View>
  );
}

function Item({
  icon,
  label,
  active,
  onPress,
}: {
  icon: SFSymbol;
  label: string;
  active?: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      style={({ pressed }) => [s.item, active && s.itemActive, pressed && s.itemPressed]}
      onPress={onPress}
    >
      <Icon
        name={icon}
        size={19}
        color={active ? colors.ember : colors.inkDim}
        weight={active ? "semibold" : "regular"}
      />
      <Text style={[s.itemLabel, active && s.itemLabelActive]}>{label}</Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.void },

  stage: { position: "absolute", top: 0, left: 0, right: 0, bottom: 0 },
  fill: { position: "absolute", top: 0, left: 0, right: 0, bottom: 0 },

  scrim: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: "rgba(0,0,0,0.6)",
  },

  panel: {
    position: "absolute",
    top: 0,
    left: 0,
    bottom: 0,
    backgroundColor: colors.raised,
    borderRightWidth: StyleSheet.hairlineWidth,
    borderRightColor: colors.line,
    paddingHorizontal: spacing.md,
  },

  who: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingVertical: spacing.sm,
  },
  whoText: { flex: 1, gap: 2 },
  whoName: { ...type.heading, color: colors.ink },
  whoSub: { ...type.small, fontSize: 13, color: colors.inkFaint },

  rule: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.line,
    marginVertical: spacing.md,
  },

  items: { gap: 2 },
  item: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingVertical: 13,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.md,
  },
  itemActive: { backgroundColor: colors.emberSoft },
  itemPressed: { backgroundColor: colors.raisedHigh },
  itemLabel: { ...type.bodyMedium, color: colors.inkDim },
  itemLabelActive: { color: colors.ink },

  spacer: { flex: 1 },

  signOut: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.md,
    paddingVertical: 13,
    paddingHorizontal: spacing.sm,
  },
  signOutText: { ...type.bodyMedium, color: colors.inkFaint },
});
