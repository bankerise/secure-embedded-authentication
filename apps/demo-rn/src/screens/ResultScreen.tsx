import React from 'react';
import { Button, ScrollView, StyleSheet, Text, View } from 'react-native';
import type { Result } from '../types';
import { describeError, formatTime } from '../types';

type Props = {
  result: Result;
  onClear: () => void;
};

/** Mirrors apps/demo-ios/Sources/Views/ResultsView.swift. */
export function ResultScreen({ result, onClear }: Props): React.JSX.Element {
  return (
    <View style={styles.root}>
      <View style={styles.header}>
        <Text style={styles.title}>Result</Text>
        <Button title="Clear" onPress={onClear} disabled={result.kind === 'idle'} />
      </View>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.content}>
        {result.kind === 'idle' && (
          <View style={styles.empty}>
            <Text style={styles.emptyText}>No session has completed yet.</Text>
            <Text style={styles.emptyHint}>Run "Start login" from the Config tab.</Text>
          </View>
        )}

        {result.kind === 'captured' && (
          <View>
            <Text style={styles.sectionTitle}>
              onCaptured — {formatTime(result.at)}
            </Text>
            {Object.keys(result.params).length === 0 ? (
              <Text style={styles.emptyHint}>(no params)</Text>
            ) : (
              Object.entries(result.params)
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([key, value]) => (
                  <View key={key} style={styles.paramRow}>
                    <Text style={[styles.mono, styles.paramKey]}>{key}</Text>
                    <Text style={[styles.mono, styles.paramValue]} selectable>
                      {value}
                    </Text>
                  </View>
                ))
            )}
          </View>
        )}

        {result.kind === 'cancelled' && (
          <OutcomeBanner
            title="onCancelled"
            detail="User dismissed the session."
            at={result.at}
            color="#e67e22"
          />
        )}

        {result.kind === 'error' && (
          <OutcomeBanner
            title="onError"
            detail={describeError(result.error)}
            at={result.at}
            color="#c0392b"
          />
        )}
      </ScrollView>
    </View>
  );
}

function OutcomeBanner({
  title,
  detail,
  at,
  color,
}: {
  title: string;
  detail: string;
  at: number;
  color: string;
}): React.JSX.Element {
  return (
    <View>
      <Text style={[styles.bannerTitle, { color }]}>{title}</Text>
      <Text style={styles.mono} selectable>
        {detail}
      </Text>
      <Text style={styles.emptyHint}>{formatTime(at)}</Text>
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
  },
  title: { fontSize: 20, fontWeight: '700' },
  scroll: { flex: 1 },
  content: { padding: 16, gap: 8 },
  empty: { alignItems: 'center', gap: 6, paddingTop: 40 },
  emptyText: { color: '#6d6d72' },
  emptyHint: { color: '#6d6d72', fontSize: 12 },
  sectionTitle: { fontSize: 13, fontWeight: '600', color: '#6d6d72', marginBottom: 8 },
  paramRow: { flexDirection: 'row', paddingVertical: 4, gap: 8 },
  paramKey: { width: 120, color: '#6d6d72' },
  paramValue: { flex: 1 },
  mono: { fontFamily: 'Menlo', fontSize: 13 },
  bannerTitle: { fontSize: 20, fontWeight: '700', marginBottom: 8 },
});
