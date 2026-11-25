
import { StatusBar } from 'expo-status-bar';
import { StyleSheet, Text, View } from 'react-native';

export default function App() {
  return (
    <View style={styles.container}>
      <StatusBar style="dark" />

      <View style={styles.logoContainer}>
        <Text style={styles.logo}>G</Text>
      </View>

      <Text style={styles.title}>Guardly</Text>

      <Text style={styles.subtitle}>
        Safer digital experiences, smarter parental controls.
      </Text>

      <View style={styles.statusContainer}>
        <View style={styles.statusDot} />
        <Text style={styles.statusText}>
          Your device is connected
        </Text>
      </View>

      <Text style={styles.footer}>
        Building a safer digital world.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F8FAFC',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  logoContainer: {
    width: 76,
    height: 76,
    borderRadius: 24,
    backgroundColor: '#F97316',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 20,
  },
  logo: {
    color: '#FFFFFF',
    fontSize: 42,
    fontWeight: '800',
  },
  title: {
    fontSize: 36,
    fontWeight: '800',
    color: '#0F172A',
  },
  subtitle: {
    fontSize: 15,
    color: '#64748B',
    textAlign: 'center',
    marginTop: 10,
    maxWidth: 280,
    lineHeight: 23,
  },
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
    marginTop: 32,
    borderWidth: 1,
    borderColor: '#E2E8F0',
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#22C55E',
    marginRight: 10,
  },
  statusText: {
    fontSize: 14,
    color: '#334155',
    fontWeight: '500',
  },
  footer: {
    position: 'absolute',
    bottom: 36,
    fontSize: 12,
    color: '#94A3B8',
  },
});
