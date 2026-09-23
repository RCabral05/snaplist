/**
 * Snaplist is a light-first app on purpose: listings are photographs of physical
 * goods, and a dark chrome casts a colour shift over every thumbnail. Chrome stays
 * paper-white and out of the way; the only saturated colour is the sell action.
 */
export const colors = {
  // ground
  paper: "#ffffff",
  paperAlt: "#f6f6f4",
  sand: "#eeece7",
  rule: "#e2e0da",
  ruleStrong: "#c9c6bd",

  // type
  ink: "#16181d",
  inkDim: "#5c6069",
  inkFaint: "#8e939c",

  // brand
  ember: "#ff5a1f",
  emberDark: "#e04407",

  // channel status
  live: "#12915a",
  pending: "#c07800",
  failed: "#d1392b",
  draft: "#8e939c",

  // aliases, so components read the same as in ios-app
  bg: "#ffffff",
  surface: "#f6f6f4",
  surfaceHigh: "#eeece7",
  border: "#e2e0da",
  borderStrong: "#c9c6bd",
  text: "#16181d",
  textMuted: "#5c6069",
  textFaint: "#8e939c",
  accent: "#ff5a1f",
  accentText: "#ffffff",
  success: "#12915a",
  danger: "#d1392b",
  white: "#ffffff",
} as const;

export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48 } as const;

export const radius = { sm: 8, md: 12, lg: 18, pill: 999 } as const;

/** Font family names as registered with expo-font (see src/app/_layout.tsx). */
export const fonts = {
  sans: "Archivo_400Regular",
  sansMedium: "Archivo_500Medium",
  sansSemi: "Archivo_600SemiBold",
  sansBold: "Archivo_700Bold",
} as const;

export const type = {
  display: { fontFamily: fonts.sansBold, fontSize: 30, letterSpacing: -0.6 },
  title: { fontFamily: fonts.sansBold, fontSize: 22, letterSpacing: -0.3 },
  heading: { fontFamily: fonts.sansSemi, fontSize: 16, letterSpacing: -0.1 },
  body: { fontFamily: fonts.sans, fontSize: 16 },
  bodyMedium: { fontFamily: fonts.sansMedium, fontSize: 16 },
  small: { fontFamily: fonts.sans, fontSize: 14 },
  label: {
    fontFamily: fonts.sansSemi,
    fontSize: 11,
    letterSpacing: 0.8,
    textTransform: "uppercase" as const,
  },
  price: { fontFamily: fonts.sansBold, fontSize: 18, letterSpacing: -0.3 },
} as const;
