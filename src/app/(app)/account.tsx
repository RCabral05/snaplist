import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button } from "@/components/button";
import { ChannelRow } from "@/components/channel-row";
import { MOCK } from "@/lib/api";
import { connect, disconnect, useConnections } from "@/lib/connections";
import { adapters } from "@/lib/marketplaces";
import { colors, spacing, type } from "@/theme";

/**
 * Connections screen. The real flows are OAuth round trips opened in a browser and
 * finished by the backend; until that exists, connecting is a local toggle so the
 * rest of the app (channel picker, publish) can be exercised.
 */
export default function AccountScreen() {
  const { isConnected } = useConnections();

  return (
    <SafeAreaView style={s.safe} edges={["top"]}>
      <ScrollView contentContainerStyle={s.body}>
        <Text style={s.title}>Account</Text>

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
                  onPress={() =>
                    connected ? disconnect(adapter.id) : connect(adapter.id)
                  }
                />
              ) : null}
            </View>
          );
        })}

        {MOCK ? (
          <Text style={s.note}>
            Running without a backend: connecting is a local toggle and publishing does not leave
            the device. Set EXPO_PUBLIC_API_URL to point at the real API.
          </Text>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.paper },
  body: { padding: spacing.md, gap: spacing.md, paddingBottom: spacing.xxl },
  title: { ...type.display, color: colors.ink },
  section: { ...type.label, color: colors.textMuted, marginTop: spacing.sm },
  channelBlock: { gap: spacing.sm },
  note: { ...type.small, color: colors.textMuted, marginTop: spacing.md, lineHeight: 20 },
});
