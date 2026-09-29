import { Pressable } from "react-native";

import { Icon } from "@/components/icon";
import { useMenu } from "@/lib/menu";
import { colors } from "@/theme";

/**
 * The hamburger. The panel it opens lives above the navigator in
 * `MenuProvider`, so this is only a button.
 */
export function AppMenu() {
  const { open } = useMenu();

  return (
    <Pressable onPress={open} hitSlop={14} accessibilityLabel="Open menu">
      <Icon name="line.3.horizontal" size={22} color={colors.ink} weight="medium" />
    </Pressable>
  );
}
