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
  ios: {
    bundleIdentifier: "com.snaplist.app",
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
    package: "com.snaplist.app",
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
