/**
 * Sentry Server Configuration with OpenTelemetry Integration
 */

import * as Sentry from '@sentry/node';
import { nodeProfilingIntegration } from '@sentry/profiling-node';
import { OpenTelemetryIntegration } from '@sentry/opentelemetry';

// Initialize Sentry with OpenTelemetry integration
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV || 'development',
  release: process.env.npm_package_version || '1.0.0',
  
  // Enable performance monitoring
  tracesSampleRate: parseFloat(process.env.SENTRY_TRACES_SAMPLE_RATE || '0.1'),
  profilesSampleRate: parseFloat(process.env.SENTRY_PROFILES_SAMPLE_RATE || '0.1'),
  
  // Integrations
  integrations: [
    // OpenTelemetry integration for trace correlation
    new OpenTelemetryIntegration({
      spanProcessor: {
        onSpan: (span) => {
          // Add Sentry-specific attributes to spans
          const transaction = Sentry.getCurrentHub().getScope()?.getTransaction();
          if (transaction) {
            span.setAttribute('sentry.transaction', transaction.name);
          }
        },
      },
    }),
    nodeProfilingIntegration(),
  ],
});

// Export configured Sentry
export default Sentry;
