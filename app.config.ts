import type { ExpoConfig, ConfigContext } from "expo/config";

// The iOS URL scheme Google Sign-In needs is just the iOS client ID reversed:
//   1234-abcd.apps.googleusercontent.com  ->  com.googleusercontent.apps.1234-abcd
const iosClientId = process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID ?? "";
const googleUrlScheme = iosClientId
  ? `com.googleusercontent.apps.${iosClientId.replace(".apps.googleusercontent.com", "")}`
  : "com.googleusercontent.apps.REPLACE_ME";

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: "Snaplist",
  slug: "snaplist",
  version: "1.0.0",
  orientation: "portrait",
  scheme: "snaplist",
  userInterfaceStyle: "light",
  backgroundColor: "#ffffff",
  owner: "buzzybuzz",
  extra: {
    eas: { projectId: "764ba08f-67fe-4639-8f92-643f01c53261" },
  },
  ios: {
    bundleIdentifier: "com.rcabral.snaplist",
    usesAppleSignIn: true,
    supportsTablet: false,
    infoPlist: {
      ITSAppUsesNonExemptEncryption: false,
      NSPhotoLibraryUsageDescription: "Snaplist uses your photo library for your profile picture.",
    },
  },
  android: {
    package: "com.rcabral.snaplist",
    adaptiveIcon: { backgroundColor: "#ffffff" },
  },
  plugins: [
    "expo-router",
    "expo-dev-client",
    "expo-apple-authentication",
    [
      "@react-native-google-signin/google-signin",
      { iosUrlScheme: googleUrlScheme },
    ],
    [
      "expo-image-picker",
      { photosPermission: "Snaplist uses your photo library for your profile picture." },
    ],

  ],
  experiments: { typedRoutes: false, reactCompiler: true },
});
