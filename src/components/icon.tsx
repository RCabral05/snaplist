import { SymbolView, type SFSymbol } from "expo-symbols";
import { View, type ColorValue } from "react-native";

import { colors } from "@/theme";

type Weight = "ultraLight" | "thin" | "light" | "regular" | "medium" | "semibold" | "bold";

/**
 * SF Symbols, wrapped so screens name an icon and a size and nothing else.
 *
 * Snaplist is iOS-only, so there is no icon font to ship and no SVG set to keep
 * in sync - the glyphs come from the OS and already match the system weight the
 * rest of the chrome is drawn at. The fallback is a blank box of the right size
 * so a missing symbol leaves the layout intact rather than collapsing a row.
 */
export function Icon({
  name,
  size = 22,
  color = colors.ink,
  weight = "regular",
}: {
  name: SFSymbol;
  size?: number;
  color?: ColorValue;
  weight?: Weight;
}) {
  return (
    <SymbolView
      name={name}
      size={size}
      tintColor={color}
      weight={weight}
      resizeMode="scaleAspectFit"
      fallback={<View style={{ width: size, height: size }} />}
    />
  );
}
