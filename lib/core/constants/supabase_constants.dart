/// Supabase Configuration — Jaramana only.
/// The publishable key is intentionally injected at build time. It is public by
/// design, but keeping it out of the repository prevents accidental reuse of
/// another project's key during development.
const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://uiutmbujkfrpaipvfvij.supabase.co',
);

const String supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: '',
);

bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
