import type { ExpoConfig, ConfigContext } from "expo/config";

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
    supportsTablet: false,
    infoPlist: {
      ITSAppUsesNonExemptEncryption: false,
      NSCameraUsageDescription:
        "Snaplist uses the camera to photograph the items you list for sale.",
      NSPhotoLibraryUsageDescription:
        "Snaplist uses your photo library to attach existing photos to a listing.",
    },
  },
  android: {
    package: "com.rcabral.snaplist",
    adaptiveIcon: { backgroundColor: "#ffffff" },
  },
  plugins: [
    "expo-router",
    "expo-dev-client",
    [
      "expo-camera",
      { cameraPermission: "Snaplist uses the camera to photograph items you list for sale." },
    ],
  ],
  experiments: { typedRoutes: false, reactCompiler: true },
});
