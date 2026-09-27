/**
 * Snaplist is light-first on purpose: listings are photographs of physical
 * goods, and dark chrome casts a colour shift over every thumbnail. That has not
 * changed - but the ground is warm paper now rather than clinical white, so a
 * product photo sits *on* something instead of dissolving into the background,
 * and cards can lift off it in true white without needing a shadow.
 *
 * The other move is typographic. Second-hand goods need to look considered, and
 * nothing does that faster than a serif: Instrument Serif carries every price,
 * title and headline, Archivo does the work of labels, buttons and inputs. One
 * voice for what is being sold, another for the machinery around it.
 */
export const colors = {
  // ground
  paper: "#FBFAF8",
  paperAlt: "#F4F2EE",
  surface: "#FFFFFF",
  sand: "#EFEBE4",
  rule: "#E7E3DB",
  ruleStrong: "#D5CFC4",

  // ink
  ink: "#15130F",
  inkDim: "#5C574D",
  inkFaint: "#948C7F",

  // brand - one saturated warm red, and a tint of it for quiet emphasis
  ember: "#DE4519",
  emberDark: "#B8350F",
  emberSoft: "#FBEDE7",

  // channel status
  live: "#11784A",
  pending: "#B07400",
  failed: "#C0341B",
  draft: "#948C7F",

  // aliases, so components read the same as in ios-app
  bg: "#FBFAF8",
  surfaceHigh: "#EFEBE4",
  border: "#E7E3DB",
  borderStrong: "#D5CFC4",
  text: "#15130F",
  textMuted: "#5C574D",
  textFaint: "#948C7F",
  accent: "#DE4519",
  accentText: "#FFFFFF",
  success: "#11784A",
  danger: "#C0341B",
  white: "#FFFFFF",
} as const;

export const spacing = { xs: 4, sm: 8, md: 16, lg: 20, xl: 32, xxl: 56 } as const;

/** Softer than before. Sharp corners read as a document rather than an app. */
export const radius = { sm: 10, md: 14, lg: 22, xl: 28, pill: 999 } as const;

/** Font family names as registered with expo-font (see src/app/_layout.tsx). */
export const fonts = {
  serif: "InstrumentSerif_400Regular",
  serifItalic: "InstrumentSerif_400Regular_Italic",
  sans: "Archivo_400Regular",
  sansMedium: "Archivo_500Medium",
  sansSemi: "Archivo_600SemiBold",
  sansBold: "Archivo_700Bold",
} as const;

export const type = {
  /** Screen-opening statements. Tight, because Instrument Serif is airy. */
  hero: { fontFamily: fonts.serif, fontSize: 46, lineHeight: 48, letterSpacing: -1.2 },
  display: { fontFamily: fonts.serif, fontSize: 34, lineHeight: 37, letterSpacing: -0.8 },
  title: { fontFamily: fonts.serif, fontSize: 26, lineHeight: 29, letterSpacing: -0.4 },
  /** The loudest thing on a product. */
  price: { fontFamily: fonts.serif, fontSize: 22, letterSpacing: -0.3 },
  priceBig: { fontFamily: fonts.serif, fontSize: 38, lineHeight: 40, letterSpacing: -1 },

  heading: { fontFamily: fonts.sansSemi, fontSize: 16, letterSpacing: -0.1 },
  body: { fontFamily: fonts.sans, fontSize: 16, letterSpacing: -0.1 },
  bodyMedium: { fontFamily: fonts.sansMedium, fontSize: 16, letterSpacing: -0.1 },
  small: { fontFamily: fonts.sans, fontSize: 14, letterSpacing: -0.05 },
  label: {
    fontFamily: fonts.sansSemi,
    fontSize: 10,
    letterSpacing: 1.1,
    textTransform: "uppercase" as const,
  },
} as const;

/** One shadow, used sparingly - on things that genuinely float. */
export const shadow = {
  lift: {
    shadowColor: "#2B241A",
    shadowOpacity: 0.09,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 8 },
    elevation: 6,
  },
} as const;
