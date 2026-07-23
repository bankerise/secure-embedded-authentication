import React from 'react';
import { Button, FlatList, StyleSheet, Text, View } from 'react-native';
import { copyToClipboard, subscribeToTelemetry } from 'sea-react-native';
import type { SEATelemetryEvent } from 'sea-react-native';

type Entry = SEATelemetryEvent & { id: string };

function propertiesText(properties: Readonly<Record<string, string>>): string {
  return Object.entries(properties)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join(', ');
}

function formattedTimestamp(timestampMs: number): string {
  return new Date(timestampMs).toLocaleTimeString([], { hour12: false });
}

/**
 * Live console for every SEAEvent SEACore emits (§20), mirroring
 * apps/demo-ios/Sources/Views/TelemetryConsoleView.swift. Subscribes only
 * while mounted — this is how the tester verifies lifecycle events
 * (AUTH_WEBVIEW_OPENED, AUTH_NAV_BLOCKED, AUTH_CAPTURE_DETECTED, ...)
 * actually fire.
 */
export function TelemetryScreen(): React.JSX.Element {
  const [entries, setEntries] = React.useState<Entry[]>([]);
  const [didCopy, setDidCopy] = React.useState(false);
  const nextId = React.useRef(0);

  React.useEffect(() => {
    const unsubscribe = subscribeToTelemetry((event) => {
      nextId.current += 1;
      const id = String(nextId.current);
      setEntries((prev) => [...prev, { ...event, id }]);
    });
    return unsubscribe;
  }, []);

  const copyableText = React.useMemo(
    () =>
      entries
        .map((e) => `[${formattedTimestamp(e.timestampMs)}] ${e.name} — ${propertiesText(e.properties)}`)
        .join('\n'),
    [entries]
  );

  return (
    <View style={styles.root}>
      <View style={styles.header}>
        <Text style={styles.title}>Telemetry ({entries.length})</Text>
        <View style={styles.actions}>
          <Button title="Clear" onPress={() => setEntries([])} disabled={entries.length === 0} />
          <Button
            title={didCopy ? 'Copied' : 'Copy all'}
            disabled={entries.length === 0}
            onPress={() => {
              copyToClipboard(copyableText);
              setDidCopy(true);
              setTimeout(() => setDidCopy(false), 1200);
            }}
          />
        </View>
      </View>

      {entries.length === 0 ? (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>No telemetry events yet.</Text>
        </View>
      ) : (
        <FlatList
          style={styles.list}
          data={[...entries].reverse()}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <View style={styles.row}>
              <View style={styles.rowHeader}>
                <Text style={styles.eventName}>{item.name}</Text>
                <Text style={styles.timestamp}>{formattedTimestamp(item.timestampMs)}</Text>
              </View>
              {Object.keys(item.properties).length > 0 && (
                <Text style={styles.properties} selectable>
                  {propertiesText(item.properties)}
                </Text>
              )}
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 4,
  },
  title: { fontSize: 18, fontWeight: '700' },
  actions: { flexDirection: 'row', gap: 8 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: '#6d6d72' },
  list: { flex: 1 },
  listContent: { paddingHorizontal: 16, paddingBottom: 16 },
  row: { paddingVertical: 6, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: '#e0e0e0' },
  rowHeader: { flexDirection: 'row', justifyContent: 'space-between' },
  eventName: { fontFamily: 'Menlo', fontWeight: '700', fontSize: 13 },
  timestamp: { fontSize: 11, color: '#6d6d72' },
  properties: { fontSize: 11, color: '#6d6d72', marginTop: 2 },
});
