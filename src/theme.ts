/**
 * Dark, and deliberately so.
 *
 * This app was light-first for one stated reason: dark chrome casts a colour
 * shift over product photographs. There are no product photographs any more -
 * the marketplace went - and nobody revisited the decision. What is left is an
 * account and a face, and a single portrait on near-black reads as the subject
 * rather than as one tile among many.
 *
 * One typeface. Archivo does everything, set large and tight at the top of the
 * scale and quiet everywhere else; the serif went with the catalogue it was
 * chosen for. Contrast carries the hierarchy instead of a second voice.
 */
export const colors = {
  // ground, darkest first
  void: "#09090B",
  paper: "#09090B",
  raised: "#131316",
  raisedHigh: "#1C1C21",
  line: "#26262C",
  lineStrong: "#36363E",

  // text
  ink: "#F6F4F0",
  inkDim: "#9B968D",
  inkFaint: "#6A665F",

  // one accent, brightened for dark - the old ember at #DE4519 muddies on black
  ember: "#FF5A2B",
  emberDim: "#C43F1A",
  emberSoft: "rgba(255,90,43,0.12)",

  success: "#3ED68B",
  danger: "#FF6B5A",
  warning: "#E9A23B",

  // aliases, so components read the same across the projects
  surface: "#131316",
  surfaceHigh: "#1C1C21",
  sand: "#26262C",
  rule: "#26262C",
  ruleStrong: "#36363E",
  border: "#26262C",
  borderStrong: "#36363E",
  paperAlt: "#131316",
  text: "#F6F4F0",
  textMuted: "#9B968D",
  textFaint: "#6A665F",
  accent: "#FF5A2B",
  accentText: "#FFFFFF",
  white: "#FFFFFF",
} as const;

export const spacing = { xs: 4, sm: 8, md: 16, lg: 20, xl: 32, xxl: 56 } as const;

export const radius = { sm: 10, md: 16, lg: 22, xl: 30, pill: 999 } as const;

/** Font family names as registered with expo-font (see src/app/_layout.tsx). */
export const fonts = {
  sans: "Archivo_400Regular",
  sansMedium: "Archivo_500Medium",
  sansSemi: "Archivo_600SemiBold",
  sansBold: "Archivo_700Bold",
} as const;

/**
 * Tight at the top, open at the bottom. Large sans only holds together with
 * negative tracking; small sans needs the opposite or it closes up on a dark
 * ground, where type always renders a touch heavier than it measures.
 */
export const type = {
  hero: { fontFamily: fonts.sansBold, fontSize: 44, lineHeight: 46, letterSpacing: -1.8 },
  display: { fontFamily: fonts.sansBold, fontSize: 32, lineHeight: 35, letterSpacing: -1.2 },
  title: { fontFamily: fonts.sansSemi, fontSize: 23, lineHeight: 27, letterSpacing: -0.7 },
  heading: { fontFamily: fonts.sansSemi, fontSize: 17, letterSpacing: -0.3 },
  body: { fontFamily: fonts.sans, fontSize: 16, letterSpacing: -0.1 },
  bodyMedium: { fontFamily: fonts.sansMedium, fontSize: 16, letterSpacing: -0.1 },
  small: { fontFamily: fonts.sans, fontSize: 14, letterSpacing: 0 },
  label: {
    fontFamily: fonts.sansSemi,
    fontSize: 10,
    letterSpacing: 1.4,
    textTransform: "uppercase" as const,
  },
} as const;

/** A black drop shadow on a black ground is invisible; this is depth, not drama. */
export const shadow = {
  lift: {
    shadowColor: "#000000",
    shadowOpacity: 0.55,
    shadowRadius: 22,
    shadowOffset: { width: 0, height: 10 },
    elevation: 8,
  },
} as const;
