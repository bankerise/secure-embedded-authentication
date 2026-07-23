import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

export type TabKey = 'config' | 'result' | 'telemetry';

const TABS: ReadonlyArray<{ key: TabKey; label: string }> = [
  { key: 'config', label: 'Config' },
  { key: 'result', label: 'Result' },
  { key: 'telemetry', label: 'Telemetry' },
];

type Props = {
  active: TabKey;
  onChange: (tab: TabKey) => void;
};

/**
 * Deliberately hand-rolled, not a navigation library (apps/demo-rn/README.md
 * — "no navigation library"): three tabs is not worth a new dependency for
 * a bridge-validation harness.
 */
export function TabBar({ active, onChange }: Props): React.JSX.Element {
  return (
    <View style={styles.root}>
      {TABS.map((tab) => (
        <Pressable key={tab.key} style={styles.tab} onPress={() => onChange(tab.key)}>
          <Text style={[styles.label, active === tab.key && styles.labelActive]}>
            {tab.label}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flexDirection: 'row',
    borderTopWidth: StyleSheet.hairlineWidth,
    borderColor: '#c7c7cc',
  },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 10 },
  label: { fontSize: 13, color: '#8e8e93' },
  labelActive: { color: '#007aff', fontWeight: '600' },
});
