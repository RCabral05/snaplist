import { Alert, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { ChannelRow } from "@/components/channel-row";
import { useAuth } from "@/lib/auth";
import { useConnections } from "@/lib/connections";
import { adapters } from "@/lib/marketplaces";
import { colors, radius, spacing, type } from "@/theme";

export default function AccountScreen() {
  const { user, profile, signOut } = useAuth();
  const { isConnected, disconnect } = useConnections();

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <ScrollView contentContainerStyle={s.body}>
        <Text style={s.title}>Account</Text>

        <View style={s.who}>
          <Text style={s.name}>{profile?.display_name || "Seller"}</Text>
          <Text style={s.email}>{user?.email ?? ""}</Text>
        </View>

        <Text style={s.section}>Channels</Text>
        {adapters.map((adapter) => {
          const connected = isConnected(adapter.id);
          return (
            <View key={adapter.id} style={s.channelBlock}>
              <ChannelRow adapter={adapter} connected={connected} />
              {adapter.requiresConnection ? (
                <Button
                  label={connected ? "Disconnect " + adapter.name : "Connect " + adapter.name}
                  variant="secondary"
                  onPress={() => {
                    if (connected) {
                      disconnect(adapter.id).catch((e) =>
                        Alert.alert("Could not disconnect", e?.message ?? ""),
                      );
                      return;
                    }
                    // Connecting is an OAuth round trip that finishes on the
                    // backend, because that is the only place the token may land.
                    Alert.alert(
                      "Not available yet",
                      "Connecting " +
                        adapter.name +
                        " needs the backend to complete the OAuth handshake and store the token. Nothing to connect to yet.",
                    );
                  }}
                />
              ) : null}
            </View>
          );
        })}

        <Button
          label="Sign out"
          variant="ghost"
          onPress={() => signOut().catch(() => {})}
          style={{ marginTop: spacing.lg }}
        />
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  body: { padding: spacing.md, gap: spacing.md, paddingBottom: spacing.xxl },
  title: { ...type.display, color: colors.ink },
  who: {
    padding: spacing.md,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    gap: 2,
  },
  name: { ...type.bodyMedium, color: colors.ink },
  email: { ...type.small, color: colors.textMuted },
  section: { ...type.label, color: colors.textMuted, marginTop: spacing.sm },
  channelBlock: { gap: spacing.sm },
});
